# Redis — принципы работы и применение

**Юдин Пётр Павлович, 5040102/60201. Презентационная команда 17.**

| Файл | Содержание |
|---|---|
| [Redis.pdf](Redis.pdf) | Презентация для выступления и сдачи |
| [Redis.pptx](Redis.pptx) | Редактируемая версия, заметки внутри слайдов |
| [src](src/README.md) | Пример кэширования месячной сводки |

Презентация содержит 14 слайдов.

## Содержание

Модель Redis, типы данных, команды и TTL, cache-aside, вытеснение и инвалидация, ревизия данных, RDB/AOF, применения, демонстрация и ограничения.

В демонстрации SQLite хранит исходные расходы, Redis — рассчитанную месячную сводку. Данные примера: три расхода на 510,00, 90,00 и 120,00 ₽, затем добавляется расход на 80,00 ₽.

## Источники

Использованы официальные англоязычные страницы Redis, проверенные 19.10.2026:

- [Начало работы](https://redis.io/docs/latest/develop/get-started/data-store/).
- [Типы данных](https://redis.io/docs/latest/develop/data-types/).
- [SET](https://redis.io/docs/latest/commands/set/), [GET](https://redis.io/docs/latest/commands/get/), [TTL](https://redis.io/docs/latest/commands/ttl/).
- [Persistence](https://redis.io/docs/latest/operate/oss_and_stack/management/persistence/).
- [Eviction](https://redis.io/docs/latest/develop/reference/eviction/).
- [Python client](https://redis.io/docs/latest/develop/clients/redis-py/connect/).
- [FAQ](https://redis.io/docs/latest/develop/get-started/faq/).
- [Pub/Sub](https://redis.io/docs/latest/develop/pubsub/).

Ссылки на источники также приведены в заметках к слайдам.
