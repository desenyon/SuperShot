"use strict";

const capture = document.querySelector("#capture");
const form = document.querySelector(".feedback");
const context = document.querySelector("#context");
const contextLabel = document.querySelector("#context-label");
const draft = document.querySelector("#draft-mark");
const mark = document.querySelector("#mark-capture");
let marking = false;
let annotation = "";
let reply = "";

function position(element, x, y) {
  element.style.left = `${Number(x) * 100}%`;
  element.style.top = `${Number(y) * 100}%`;
}

function updateContext() {
  contextLabel.textContent = [reply, annotation].filter(Boolean).join(" · ");
  context.hidden = !contextLabel.textContent;
}

function setMarking(enabled) {
  marking = enabled;
  capture.classList.toggle("marking", enabled);
  mark?.setAttribute("aria-pressed", String(enabled));
  if (mark) mark.textContent = enabled ? "Click a point on the image" : "Mark a point";
}

document.querySelectorAll(".marker").forEach((marker) => {
  position(marker, marker.dataset.x, marker.dataset.y);
});

mark?.addEventListener("click", () => setMarking(!marking));
capture.addEventListener("click", (event) => {
  if (!marking) return;
  const bounds = capture.getBoundingClientRect();
  const x = Math.min(1, Math.max(0, (event.clientX - bounds.left) / bounds.width)).toFixed(4);
  const y = Math.min(1, Math.max(0, (event.clientY - bounds.top) / bounds.height)).toFixed(4);
  form.elements.x.value = x;
  form.elements.y.value = y;
  position(draft, x, y);
  draft.hidden = false;
  annotation = "Image point attached";
  setMarking(false);
  updateContext();
  form.elements.body.focus();
});

document.querySelector("#set-time")?.addEventListener("click", () => {
  form.elements.seconds.value = capture.currentTime.toFixed(2);
});

document.querySelectorAll("[data-seconds]").forEach((button) => {
  button.addEventListener("click", () => {
    capture.currentTime = Number(button.dataset.seconds);
    capture.scrollIntoView({block: "nearest"});
  });
});

document.querySelectorAll("[data-reply]").forEach((button) => {
  button.addEventListener("click", () => {
    form.elements.reply.value = button.dataset.reply;
    reply = `Replying to ${button.dataset.name}`;
    updateContext();
    form.elements.body.focus();
  });
});

document.querySelector("#clear-context").addEventListener("click", () => {
  form.elements.reply.value = "";
  if (form.elements.x) form.elements.x.value = "";
  if (form.elements.y) form.elements.y.value = "";
  annotation = "";
  reply = "";
  draft.hidden = true;
  updateContext();
});
