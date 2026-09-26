(function () {
  "use strict";

  var ICON_CHECK =
    '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5l5 5L20 6.5"/></svg>';
  var ICON_CLOSE =
    '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 5l14 14"/><path d="M19 5L5 19"/></svg>';
  var ICON_EYE =
    '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>';
  var ICON_EYE_OFF =
    '<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 4.5l17 17"/><path d="M6.4 6.9C4 8.5 2 12 2 12s3.6 7 10 7c1.9 0 3.5-.5 4.9-1.3"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/><path d="M14.3 6.2A9.8 9.8 0 0 1 22 12s-.7 1.4-2.1 2.9"/></svg>';

  function initPasswordToggles() {
    document.querySelectorAll("[data-password-toggle]").forEach(function (toggle) {
      toggle.addEventListener("click", function () {
        var input = document.getElementById(toggle.getAttribute("data-password-toggle"));
        if (!input) return;
        var showing = input.type === "text";
        input.type = showing ? "password" : "text";
        toggle.innerHTML = showing ? ICON_EYE : ICON_EYE_OFF;
        toggle.setAttribute("aria-label", showing ? "Show password" : "Hide password");
      });
    });
  }

  function initModal() {
    var modal = document.getElementById("create-page-modal");
    if (!modal) return;

    function open() {
      modal.hidden = false;
    }

    function close() {
      modal.hidden = true;
    }

    document.querySelectorAll("[data-modal-open]").forEach(function (trigger) {
      trigger.addEventListener("click", open);
    });

    modal.querySelectorAll("[data-modal-close]").forEach(function (trigger) {
      trigger.addEventListener("click", close);
    });

    modal.addEventListener("click", function (event) {
      if (event.target === modal) close();
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && !modal.hidden) close();
    });
  }

  function initHandleAvailability() {
    var handleInput = document.getElementById("create-page-handle");
    var checkBtn = document.getElementById("check-handle-btn");
    var status = document.getElementById("handle-status");
    var submitBtn = document.getElementById("create-page-submit");
    if (!handleInput || !checkBtn || !status || !submitBtn) return;

    var checkUrl = checkBtn.getAttribute("data-check-url");

    function setStatus(kind, message) {
      status.className = "handle-status" + (kind ? " handle-status-" + kind : "");
      if (kind === "available") {
        status.innerHTML = ICON_CHECK + "<span>" + message + "</span>";
      } else if (kind === "taken" || kind === "invalid") {
        status.innerHTML = ICON_CLOSE + "<span>" + message + "</span>";
      } else if (kind === "checking") {
        status.textContent = message;
      } else {
        status.innerHTML = "";
      }
    }

    function resetStatus() {
      setStatus(null, "");
      submitBtn.disabled = true;
    }

    checkBtn.disabled = handleInput.value.trim() === "";

    handleInput.addEventListener("input", function () {
      checkBtn.disabled = handleInput.value.trim() === "";
      resetStatus();
    });

    checkBtn.addEventListener("click", function () {
      var handle = handleInput.value.trim();
      if (!handle) {
        setStatus("taken", "Enter a handle first.");
        submitBtn.disabled = true;
        return;
      }

      setStatus("checking", "Checking availability...");

      fetch(checkUrl + "?handle=" + encodeURIComponent(handle), {
        headers: { "X-Requested-With": "XMLHttpRequest" },
      })
        .then(function (response) {
          return response.json();
        })
        .then(function (data) {
          var kind = data.status === "available" ? "available" : "taken";
          setStatus(kind, data.message);
          submitBtn.disabled = data.status !== "available";
        })
        .catch(function () {
          setStatus("taken", "Something went wrong. Try again.");
          submitBtn.disabled = true;
        });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    initPasswordToggles();
    initModal();
    initHandleAvailability();
  });
})();
