"""Учебный пример: SQLite как источник данных, Redis как кэш сводки.

Запуск: python demo.py
Полный веб-сервис и аутентификация в этот пример не входят.
"""
from __future__ import annotations

import argparse
import json
import re
import socket
import sqlite3
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from uuid import uuid4

import redis
from redis.backoff import NoBackoff
from redis.retry import Retry


def redis_client(url: str) -> redis.Redis:
    return redis.Redis.from_url(
        url, decode_responses=True, socket_timeout=0.2,
        socket_connect_timeout=0.2, retry=Retry(NoBackoff(), 0),
    )


def amount_minor(value: str) -> int:
    value = value.strip().replace(",", ".")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]{1,2})?", value):
        raise ValueError("Сумма должна содержать не более двух десятичных знаков")
    amount = Decimal(value)
    if not Decimal("0.01") <= amount <= Decimal("999999999.99"):
        raise ValueError("Сумма вне допустимого диапазона")
    return int(amount * 100)


def money(value: int) -> str:
    return f"{value // 100}.{value % 100:02d}"


def month_bounds(month: str) -> tuple[str, str]:
    if not re.fullmatch(r"[0-9]{4}-[0-9]{2}", month):
        raise ValueError("Ожидается месяц YYYY-MM")
    year, number = map(int, month.split("-"))
    first = date(year, number, 1)
    next_month = date(year + (number == 12), 1 if number == 12 else number + 1, 1)
    return first.isoformat(), next_month.isoformat()


class Repository:
    def __init__(self) -> None:
        self.db = sqlite3.connect(":memory:")
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.executescript("""
            CREATE TABLE users (
                id INTEGER PRIMARY KEY, login TEXT NOT NULL UNIQUE,
                revision INTEGER NOT NULL DEFAULT 0 CHECK(revision >= 0)
            );
            CREATE TABLE categories (
                id INTEGER PRIMARY KEY, user_id INTEGER NOT NULL REFERENCES users(id),
                name TEXT NOT NULL, UNIQUE(id, user_id)
            );
            CREATE TABLE expenses (
                id INTEGER PRIMARY KEY,
                user_id INTEGER NOT NULL REFERENCES users(id),
                category_id INTEGER NOT NULL,
                amount_minor INTEGER NOT NULL CHECK(amount_minor > 0),
                expense_date TEXT NOT NULL,
                FOREIGN KEY(category_id, user_id) REFERENCES categories(id, user_id)
            );
            INSERT INTO users(id,login) VALUES (1,'user_a'), (2,'user_b');
            INSERT INTO categories(id,user_id,name) VALUES
                (1,1,'Продукты'), (2,1,'Транспорт'), (3,2,'Продукты');
        """)
        self.aggregate_queries = 0
        for row in [(1,1,"510.00","2026-10-01"), (1,2,"90.00","2026-10-02"),
                    (1,1,"120.00","2026-10-03"), (1,1,"200.00","2026-09-30"),
                    (2,3,"999.99","2026-10-01")]:
            self.add_expense(*row)

    def revision(self, user_id: int) -> int:
        row = self.db.execute("SELECT revision FROM users WHERE id=?", (user_id,)).fetchone()
        if row is None:
            raise ValueError("Пользователь не найден")
        return row[0]

    def add_expense(self, user_id: int, category_id: int, amount: str, day: str) -> int:
        minor = amount_minor(amount)
        date.fromisoformat(day)
        with self.db:
            row = self.db.execute(
                "SELECT id FROM categories WHERE id=? AND user_id=?", (category_id, user_id)
            ).fetchone()
            if row is None:
                raise ValueError("Категория не принадлежит пользователю")
            cursor = self.db.execute(
                "INSERT INTO expenses(user_id,category_id,amount_minor,expense_date) VALUES (?,?,?,?)",
                (user_id, category_id, minor, day),
            )
            self.db.execute("UPDATE users SET revision=revision+1 WHERE id=?", (user_id,))
        return cursor.lastrowid

    def rename_category(self, user_id: int, category_id: int, name: str) -> None:
        name = name.strip()
        if not 1 <= len(name) <= 50:
            raise ValueError("Недопустимое имя")
        with self.db:
            cur = self.db.execute(
                "UPDATE categories SET name=? WHERE id=? AND user_id=?",
                (name, category_id, user_id),
            )
            if cur.rowcount != 1:
                raise ValueError("Категория не найдена")
            self.db.execute("UPDATE users SET revision=revision+1 WHERE id=?", (user_id,))

    def aggregate(self, user_id: int, month: str) -> dict:
        start, end = month_bounds(month)
        self.revision(user_id)
        rows = self.db.execute("""
            SELECT c.id, c.name, SUM(e.amount_minor)
            FROM expenses e JOIN categories c ON c.id=e.category_id AND c.user_id=e.user_id
            WHERE e.user_id=? AND e.expense_date>=? AND e.expense_date<?
            GROUP BY c.id,c.name ORDER BY c.id
        """, (user_id, start, end)).fetchall()
        self.aggregate_queries += 1
        return {
            "user_id": user_id, "month": month,
            "total": money(sum(row[2] for row in rows)),
            "categories": [{"id": row[0], "name": row[1], "amount": money(row[2])} for row in rows],
        }

    def close(self) -> None:
        self.db.close()


def valid_cached(value: object, user_id: int, month: str) -> bool:
    if not isinstance(value, dict) or value.get("user_id") != user_id or value.get("month") != month:
        return False
    if not isinstance(value.get("total"), str) or not re.fullmatch(r"[0-9]+\.[0-9]{2}", value["total"]):
        return False
    rows = value.get("categories")
    if not isinstance(rows, list):
        return False
    ids = set()
    total = Decimal("0")
    for row in rows:
        if not isinstance(row, dict) or type(row.get("id")) is not int or row["id"] in ids:
            return False
        if not isinstance(row.get("name"), str) or not isinstance(row.get("amount"), str):
            return False
        if not re.fullmatch(r"[0-9]+\.[0-9]{2}", row["amount"]):
            return False
        ids.add(row["id"])
        total += Decimal(row["amount"])
    return total == Decimal(value["total"])


@dataclass
class Result:
    summary: dict
    source: str
    key: str
    cache_written: bool = False


class SummaryService:
    def __init__(self, repository: Repository, client: redis.Redis,
                 prefix: str | None = None, ttl: int = 60) -> None:
        if ttl < 1:
            raise ValueError("TTL должен быть положительным")
        self.repository = repository
        self.client = client
        self.prefix = prefix or f"redis-demo:yudin:{uuid4().hex[:10]}"
        self.ttl = ttl
        self.written_keys: set[str] = set()

    def key(self, user_id: int, month: str, revision: int) -> str:
        return f"{self.prefix}:v1:u:{user_id}:r:{revision}:m:{month}"

    def read(self, user_id: int, month: str) -> Result:
        month_bounds(month)
        revision = self.repository.revision(user_id)
        key = self.key(user_id, month, revision)
        available = True
        try:
            raw = self.client.get(key)
            if raw is not None:
                try:
                    value = json.loads(raw)
                except (json.JSONDecodeError, TypeError):
                    value = None
                if valid_cached(value, user_id, month):
                    return Result(value, "CACHE", key)
        except redis.RedisError:
            available = False
        summary = self.repository.aggregate(user_id, month)
        same_revision = self.repository.revision(user_id) == revision
        written = False
        if available and same_revision:
            try:
                self.client.set(key, json.dumps(summary, ensure_ascii=False), ex=self.ttl)
                self.written_keys.add(key)
                written = True
            except redis.RedisError:
                available = False
        return Result(summary, "DB" if available else "DB (Redis unavailable)", key, written)

    def cleanup(self) -> None:
        # Только созданные этим запуском ключи. FLUSHDB / FLUSHALL не используются.
        if self.written_keys:
            try:
                self.client.delete(*self.written_keys)
            except redis.RedisError:
                pass


def run_demo(url: str) -> None:
    client = redis_client(url)
    try:
        client.ping()
    except redis.RedisError as exc:
        raise SystemExit("Redis недоступен. Запустите сервер по README и повторите.") from exc
    repo = Repository()
    service = SummaryService(repo, client)
    try:
        print("Исходные расходы пользователя A за октябрь: 510 + 90 + 120 = 720.00 RUB")
        for title in ["1. Первый запрос", "2. Повторный запрос"]:
            result = service.read(1, "2026-10")
            print(f"{title}: {result.source}, total={result.summary['total']}, aggregate_queries={repo.aggregate_queries}")
        repo.add_expense(1, 1, "80.00", "2026-10-04")
        result = service.read(1, "2026-10")
        print(f"3. После добавления 80.00: {result.source}, total={result.summary['total']}, aggregate_queries={repo.aggregate_queries}")
        result = service.read(1, "2026-10")
        print(f"4. Повтор после изменения: {result.source}, total={result.summary['total']}, aggregate_queries={repo.aggregate_queries}")
        # Зарезервированный порт без listen даёт настоящий отказ соединения.
        with socket.socket() as blocked:
            blocked.bind(("127.0.0.1", 0))
            unavailable = redis_client(f"redis://127.0.0.1:{blocked.getsockname()[1]}/0")
            fallback = SummaryService(repo, unavailable, prefix=service.prefix)
            result = fallback.read(1, "2026-10")
            print(f"5. Недоступное соединение Redis: {result.source}, total={result.summary['total']}")
            unavailable.close()
        print("Количество aggregate_queries считает только агрегации, а не все SQL-запросы.")
        print("Ключи этого запуска удаляются. Данные других приложений не затрагиваются.")
    finally:
        service.cleanup()
        repo.close()
        client.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--redis-url", default="redis://127.0.0.1:6379/0")
    run_demo(parser.parse_args().redis_url)

