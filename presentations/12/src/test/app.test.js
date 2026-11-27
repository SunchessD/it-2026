// Тесты API. Запускаются командой npm test (встроенный запуск тестов Node.js + supertest).
import test from "node:test";
import assert from "node:assert";
import request from "supertest";
import createApp from "../app.js";

test("список задач сначала пуст", async () => {
  const res = await request(createApp()).get("/api/tasks");
  assert.strictEqual(res.status, 200);
  assert.deepStrictEqual(res.body, []);
});

test("задачу можно добавить, отметить выполненной и удалить", async () => {
  const app = createApp();

  const created = await request(app).post("/api/tasks").send({ title: "Изучить npm" });
  assert.strictEqual(created.status, 201);
  assert.strictEqual(created.body.title, "Изучить npm");

  const toggled = await request(app).patch("/api/tasks/" + created.body.id);
  assert.strictEqual(toggled.body.done, true);

  const removed = await request(app).delete("/api/tasks/" + created.body.id);
  assert.strictEqual(removed.status, 204);
  assert.deepStrictEqual((await request(app).get("/api/tasks")).body, []);
});

test("пустое название задачи отклоняется", async () => {
  const res = await request(createApp()).post("/api/tasks").send({ title: "   " });
  assert.strictEqual(res.status, 400);
});
