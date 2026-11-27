"""Интеграционные проверки с настоящим Redis. REDIS_URL задаёт адрес стенда."""
import json
import os
import socket
import time
import unittest

from demo import Repository, SummaryService, amount_minor, redis_client


class CacheTests(unittest.TestCase):
    def setUp(self):
        self.client = redis_client(os.environ.get("REDIS_URL", "redis://127.0.0.1:6379/0"))
        self.client.ping()
        self.repo = Repository()
        self.service = SummaryService(self.repo, self.client)

    def tearDown(self):
        self.service.cleanup()
        self.repo.close()
        self.client.close()

    def test_miss_then_hit_and_exact_total(self):
        a = self.service.read(1, "2026-10")
        b = self.service.read(1, "2026-10")
        self.assertEqual((a.source, b.source), ("DB", "CACHE"))
        self.assertEqual(a.summary["total"], "720.00")
        self.assertEqual(a.summary, b.summary)
        self.assertEqual(self.repo.aggregate_queries, 1)

    def test_month_and_owner_isolation(self):
        self.assertEqual(self.service.read(1, "2026-09").summary["total"], "200.00")
        self.assertEqual(self.service.read(2, "2026-10").summary["total"], "999.99")
        self.assertEqual(self.service.read(1, "2026-10").summary["total"], "720.00")
        self.assertEqual(self.service.read(1, "2026-11").summary["total"], "0.00")

    def test_revision_prevents_stale_hit(self):
        old = self.service.read(1, "2026-10")
        self.repo.add_expense(1, 1, "80.00", "2026-10-04")
        new = self.service.read(1, "2026-10")
        self.assertNotEqual(old.key, new.key)
        self.assertEqual(new.summary["total"], "800.00")
        self.assertEqual(new.source, "DB")
        self.assertEqual(self.service.read(1, "2026-10").source, "CACHE")

    def test_category_rename_changes_revision(self):
        self.service.read(1, "2026-10")
        self.repo.rename_category(1, 1, "Еда")
        result = self.service.read(1, "2026-10")
        self.assertEqual(result.summary["total"], "720.00")
        self.assertEqual(result.summary["categories"][0]["name"], "Еда")

    def test_expired_key_is_recomputed(self):
        self.service.ttl = 1
        result = self.service.read(1, "2026-10")
        self.assertGreaterEqual(self.client.ttl(result.key), 0)
        time.sleep(1.1)
        self.assertEqual(self.service.read(1, "2026-10").source, "DB")
        self.assertEqual(self.repo.aggregate_queries, 2)

    def test_bad_cache_is_recomputed(self):
        result = self.service.read(1, "2026-10")
        for bad in ["not-json", json.dumps({"total": "bad"}), json.dumps({"user_id": 2, "month": "2026-10"})]:
            self.client.set(result.key, bad, ex=60)
            self.assertEqual(self.service.read(1, "2026-10").summary["total"], "720.00")
            self.assertEqual(self.service.read(1, "2026-10").source, "CACHE")

    def test_real_connection_failure_falls_back(self):
        with socket.socket() as blocked:
            blocked.bind(("127.0.0.1", 0))
            client = redis_client(f"redis://127.0.0.1:{blocked.getsockname()[1]}/0")
            try:
                result = SummaryService(self.repo, client).read(1, "2026-10")
                self.assertEqual(result.summary["total"], "720.00")
                self.assertEqual(result.source, "DB (Redis unavailable)")
            finally:
                client.close()

    def test_revision_change_during_calculation_is_not_cached(self):
        original = self.repo.aggregate
        def changing(user_id, month):
            result = original(user_id, month)
            self.repo.add_expense(1, 1, "80.00", "2026-10-04")
            return result
        self.repo.aggregate = changing
        result = self.service.read(1, "2026-10")
        self.assertFalse(result.cache_written)
        self.assertIsNone(self.client.get(result.key))
        self.repo.aggregate = original
        self.assertEqual(self.service.read(1, "2026-10").summary["total"], "800.00")

    def test_money_and_cross_owner_validation(self):
        self.assertEqual(amount_minor("0,10"), 10)
        self.assertEqual(amount_minor("0.20"), 20)
        for bad in ["0", "-1", "12.345", "NaN", "1000000000.00"]:
            with self.assertRaises(ValueError):
                amount_minor(bad)
        revision = self.repo.revision(1)
        with self.assertRaises(ValueError):
            self.repo.add_expense(1, 3, "1.00", "2026-10-04")
        self.assertEqual(self.repo.revision(1), revision)


if __name__ == "__main__":
    unittest.main(verbosity=2)

