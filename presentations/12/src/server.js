// Точка входа: запускает сервер на порту 3000.
import createApp from "./app.js";

const PORT = process.env.PORT || 3000;
createApp().listen(PORT, () => {
  console.log(`Сервер запущен: http://localhost:${PORT}`);
});
