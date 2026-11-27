// Express-приложение: REST API для списка задач.
import express from "express";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function createApp() {
  const app = express();
  let tasks = [];
  let nextId = 1;

  app.use(express.json());

  // Страница и скрипт для браузера лежат в папке public
  app.use(express.static(path.join(__dirname, "public")));

  // Библиотека dayjs, установленная через npm, отдаётся браузеру напрямую из node_modules
  app.use("/vendor/dayjs", express.static(path.join(__dirname, "node_modules", "dayjs")));

  app.get("/api/tasks", (req, res) => {
    res.json(tasks);
  });

  app.post("/api/tasks", (req, res) => {
    const title = String(req.body.title || "").trim();
    if (!title) {
      return res.status(400).json({ error: "Название задачи не может быть пустым" });
    }
    const task = { id: nextId++, title, done: false, createdAt: Date.now() };
    tasks.push(task);
    res.status(201).json(task);
  });

  app.patch("/api/tasks/:id", (req, res) => {
    const task = tasks.find((t) => t.id === Number(req.params.id));
    if (!task) {
      return res.status(404).json({ error: "Задача не найдена" });
    }
    task.done = !task.done;
    res.json(task);
  });

  app.delete("/api/tasks/:id", (req, res) => {
    const before = tasks.length;
    tasks = tasks.filter((t) => t.id !== Number(req.params.id));
    res.status(before === tasks.length ? 404 : 204).end();
  });

  return app;
}

export default createApp;
