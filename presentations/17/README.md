# Redis: принципы работы и применение

Юдин Пётр Павлович, группа 5040102/60201. Презентационная команда 17.

| Файл | Содержание |
| --- | --- |
| [Redis.pdf](Redis.pdf) | Презентация, 17 слайдов |
| [src](src/README.md) | Исходники, команды и инструкция запуска примера |

На Windows запуск начинается с [инструкции в src](src/README.md): `run-windows.cmd test` выполняет проверки, `run-windows.cmd demo` показывает пример.

## Содержание

Модель Redis, выполнение команд, типы данных, ключи и TTL, атомарность, cache-aside, вытеснение и инвалидация, ревизия данных, RDB/AOF, применения, демонстрация и разбор кода, ограничения, применение в проекте.

В примере SQLite хранит исходные расходы, Redis хранит рассчитанную месячную сводку. Три расхода на 510,00, 90,00 и 120,00 рубля дают итог 720,00. После добавления 80,00 итог становится 800,00. Программа показывает первый расчёт, повторное чтение из кэша, обновление результата и работу при недоступном Redis.

Консольный пример не является готовым веб-сервисом. Django и PostgreSQL на слайде 16 относятся к проектируемому сервису учёта расходов.

## Источники

Официальная документация Redis, проверена 10.11.2026:

- [Типы данных](https://redis.io/docs/latest/develop/data-types/).
- [SET](https://redis.io/docs/latest/commands/set/), [GET](https://redis.io/docs/latest/commands/get/), [TTL](https://redis.io/docs/latest/commands/ttl/), [INCR](https://redis.io/docs/latest/commands/incr/).
- [Выполнение команд и задержки](https://redis.io/docs/latest/operate/oss_and_stack/management/optimization/latency/).
- [Транзакции](https://redis.io/docs/latest/develop/using-commands/transactions/).
- [Persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/).
- [Eviction](https://redis.io/docs/latest/develop/reference/eviction/).
- [Python-клиент](https://redis.io/docs/latest/develop/clients/redis-py/connect/).
- [Pub/Sub](https://redis.io/docs/latest/develop/pubsub/).

