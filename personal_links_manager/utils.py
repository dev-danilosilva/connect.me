import re

HANDLE_RE = re.compile(r"^[a-z0-9-]+$")

# Mirrors linktree-ui/src/Api.elm's `reservedHandles` list.
RESERVED_HANDLES = {
    "admin",
    "support",
    "help",
    "about",
    "contact",
    "api",
    "login",
    "register",
    "dashboard",
    "experimental",
}


def humanize_handle(handle: str) -> str:
    """"my-cool-page" -> "My Cool Page" (mirrors Page.Dashboard.elm's humanizeHandle)."""
    return " ".join(word[:1].upper() + word[1:] for word in handle.split("-") if word)
