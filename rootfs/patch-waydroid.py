#!/usr/bin/env python3
"""Anti-freeze patch for waydroid (run inside the rootfs chroot).

Upstream waydroid 1.6.x suspend() knows only suspend_action == "stop"
(stop the session) with freeze-the-container as the fallback for every
other value — there is NO "none". On a desktop the freeze is fatal:
Android suspends on its own screen-off timer, the container freezes, all
app windows vanish, and nothing unfreezes it (spike finding F10-rev,
2026-08-30; same patch ddcash carried). This adds the "none" branch.

The assert makes upstream drift loud: if waydroid changes this code, the
rootfs build fails and the patch gets re-verified instead of silently
half-applying (working agreement #2, Risk R3).
"""
P = "/usr/lib/waydroid/tools/services/hardware_manager.py"

OLD = """        if cfg["waydroid"]["suspend_action"] == "stop":
            tools.actions.session_manager.stop(args)
        else:
            tools.actions.container_manager.freeze(args)"""

NEW = """        if cfg["waydroid"]["suspend_action"] == "stop":
            tools.actions.session_manager.stop(args)
        elif cfg["waydroid"]["suspend_action"] == "none":
            pass  # Windroid: never suspend on a desktop
        else:
            tools.actions.container_manager.freeze(args)"""

s = open(P).read()
if NEW in s:
    print("anti-freeze patch already applied")
else:
    assert OLD in s, (
        "hardware_manager.py changed upstream - re-verify the anti-freeze "
        "patch against the new waydroid version")
    open(P, "w").write(s.replace(OLD, NEW))
    print("anti-freeze patch applied")
