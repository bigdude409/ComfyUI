"""Centralized MIME type initialization.

Call init_mime_types() once at startup to initialize the MIME type database
and register all custom types used across ComfyUI.
"""

import mimetypes

_initialized = False


def init_mime_types():
    """Initialize the MIME type database and register all custom types.

    Safe to call multiple times; only runs once.
    """
    global _initialized
    if _initialized:
        return
    _initialized = True

    mimetypes.init()

    # Web types (used by server.py for static file serving)
    _web_types = (
        ('application/javascript; charset=utf-8', '.js'),
        ('image/webp', '.webp'),
        ('image/svg+xml', '.svg'),
    )
    for _ctype, _ext in _web_types:
        mimetypes.add_type(_ctype, _ext)

    # aiohttp >= 3.13 serves static files (web.FileResponse / web.static) through a
    # private CONTENT_TYPES MimeTypes instance that does NOT consult the global
    # `mimetypes` registry above. Without this, .webp is sent as
    # application/octet-stream and browsers won't render it, so the "Browse
    # Templates" gallery thumbnails go blank even though every asset returns 200.
    # Register the web types into that instance too. Guarded against aiohttp
    # internals changing across versions.
    try:
        from aiohttp import web_fileresponse
        for _ctype, _ext in _web_types:
            web_fileresponse.CONTENT_TYPES.add_type(_ctype, _ext)
    except Exception:
        pass

    # Model and data file types (used by asset scanning / metadata extraction)
    mimetypes.add_type("application/safetensors", ".safetensors")
    mimetypes.add_type("application/safetensors", ".sft")
    mimetypes.add_type("application/pytorch", ".pt")
    mimetypes.add_type("application/pytorch", ".pth")
    mimetypes.add_type("application/pickle", ".ckpt")
    mimetypes.add_type("application/pickle", ".pkl")
    mimetypes.add_type("application/gguf", ".gguf")
    mimetypes.add_type("application/yaml", ".yaml")
    mimetypes.add_type("application/yaml", ".yml")
