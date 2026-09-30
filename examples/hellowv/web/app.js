// The bindings exposed from OCaml (see hellowv.ml) are available as
// window.add(...), window.os_type() and window.pick_file(), each returning a
// Promise.

const out = document.querySelector("#out");

const show = (value) => {
  out.textContent = value;
};

document
  .querySelector("#btn-add")
  .addEventListener("click", () => add(20, 22).then(show));

document
  .querySelector("#btn-os")
  .addEventListener("click", () => os_type().then(show));

// pick_file() shows a *native* file browser, driven from OCaml. The promise
// resolves with the chosen path, or with null when the user cancels.
document.querySelector("#btn-file").addEventListener("click", () => {
  pick_file().then((path) => show(path === null ? "(cancelled)" : path));
});
