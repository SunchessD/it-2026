// Код, который выполняется в браузере: общается с сервером через fetch.
// Подключён в index.html как ES-модуль (type="module").
const list = document.getElementById("list");
const form = document.getElementById("form");
const input = document.getElementById("title");

async function load() {
  const tasks = await (await fetch("/api/tasks")).json();
  list.innerHTML = "";
  for (const t of tasks) {
    const li = document.createElement("li");
    if (t.done) li.className = "done";

    const title = document.createElement("span");
    title.className = "title";
    title.textContent = t.title;
    title.onclick = async () => { await fetch("/api/tasks/" + t.id, { method: "PATCH" }); load(); };

    const time = document.createElement("span");
    time.className = "time";
    time.textContent = dayjs(t.createdAt).format("DD.MM.YYYY HH:mm"); // dayjs из npm

    const del = document.createElement("button");
    del.className = "del";
    del.textContent = "Удалить";
    del.onclick = async () => { await fetch("/api/tasks/" + t.id, { method: "DELETE" }); load(); };

    li.append(title, time, del);
    list.append(li);
  }
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const title = input.value.trim();
  if (!title) return;
  await fetch("/api/tasks", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ title }),
  });
  input.value = "";
  load();
});

load();
