// Keep xdg_popup grabs (GTK4 popovers: rename, new folder, search) alive
// while the on-screen keyboard is shown and tapped.
//
// Hyprland drops a seat grab whenever a refocus lands on a surface the grab
// doesn't accept (CInputManager::mouseMoveUnified, see its FIXME: popup grabs
// should be keyboard-only). The OSK is a separate layer surface, and two
// refocuses hit that check: the one when the OSK maps (a popover's entry took
// focus, so the OSK appears) and the one on every key tap. Either closes the
// popover, and the keystroke (sent via ydotool) goes nowhere.
//
// So the OSK joins the active grab: when its layer opens (before the map
// refocus) and on every touch or button press (before that refocus). A press
// anywhere else still dismisses the popup as usual.
//
// Also a touch guard for unlocking (Hyprland 0.57.2): while the lock client
// tears its surfaces down, the session still counts as locked but the lock
// surface's wl_surface is gone. CInputManager::onTouchDown then hands a null
// surface to CSeatManager::sendTouchDown, which dereferences it (SEGV in
// CWLSurfaceResource::client). A finger landing in that gap is dropped here,
// before Hyprland picks a target; the touch-up of a dropped touch-down is
// harmless (no touch focus).
#include <hyprland/src/plugins/PluginAPI.hpp>
#include <hyprland/src/event/EventBus.hpp>
#include <hyprland/src/managers/SeatManager.hpp>
#include <hyprland/src/desktop/state/LayerState.hpp>
#include <hyprland/src/desktop/view/LayerSurface.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/protocols/SessionLock.hpp>
#include <hyprland/src/managers/SessionLockManager.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/desktop/state/FocusState.hpp>
#include <hyprland/src/output/Monitor.hpp>
#include <hyprland/src/devices/ITouch.hpp>

#include <stdexcept>
#include <string>

namespace {
    CHyprSignalListener g_touchDown, g_mouseButton, g_layerOpened;

    // "osk" is the layer namespace on-screen keyboards use (squeekboard's);
    // give a custom keyboard the same namespace to be covered.
    bool isOsk(const PHLLS& ls) {
        return ls && ls->m_namespace == "osk";
    }

    // The root and any subsurfaces: the hit test returns the exact surface
    // under the finger. Not gated on mapped(): the layer is still mapping
    // when it opens.
    void joinGrab(const PHLLS& ls) {
        const auto& grab = g_pSeatManager->m_seatGrab;
        const auto  root = ls->resource();
        if (!grab || !root)
            return;
        root->breadthfirst(
            [&grab](SP<CWLSurfaceResource> surface, const Vector2D&, void*) {
                if (surface && !grab->accepts(surface))
                    grab->add(surface);
            },
            nullptr);
    }

    // Same monitor choice as CInputManager::onTouchDown.
    bool lockSurfaceGone(const ITouch::SDownEvent& e) {
        if (!g_pSessionLockManager || !g_pSessionLockManager->isSessionLocked() || !e.device)
            return false;
        auto monitor = State::monitorState()->query().name(!e.device->m_boundOutput.empty() ? e.device->m_boundOutput : "").run();
        monitor      = monitor ? monitor : Desktop::focusState()->monitor();
        if (!monitor)
            return false;
        const auto lock = g_pSessionLockManager->getSessionLockSurfaceForMonitor(monitor->m_id);
        return !lock || !lock->surface || !lock->surface->surface();
    }

    void joinGrabAll() {
        if (!g_pSeatManager->m_seatGrab)
            return;
        for (const auto& ls : Desktop::layerState()->layers()) {
            if (isOsk(ls))
                joinGrab(ls);
        }
    }
}

APICALL EXPORT std::string PLUGIN_API_VERSION() {
    return HYPRLAND_API_VERSION;
}

APICALL EXPORT PLUGIN_DESCRIPTION_INFO PLUGIN_INIT(HANDLE handle) {
    if (std::string(__hyprland_api_get_hash()) != __hyprland_api_get_client_hash()) {
        HyprlandAPI::addNotification(handle, "[osk-popup] built for a different Hyprland; not loaded",
                                     CHyprColor{1.0, 0.2, 0.2, 1.0}, 8000);
        throw std::runtime_error("osk-popup: Hyprland version mismatch");
    }
    auto& events  = Event::bus()->m_events;
    g_layerOpened = events.layer.opened.listen([](const auto& ls) {
        if (isOsk(ls))
            joinGrab(ls);
    });
    g_touchDown   = events.input.touch.down.listen([](const auto& e, auto& info) {
        if (lockSurfaceGone(e)) {
            info.cancelled = true;
            return;
        }
        joinGrabAll();
    });
    g_mouseButton = events.input.mouse.button.listen([](const auto&, auto&) { joinGrabAll(); });
    return {"osk-popup", "Keep popups open while the on-screen keyboard is used; drop touches during unlock", "asphalt", "2"};
}

APICALL EXPORT void PLUGIN_EXIT() {
    g_layerOpened.reset();
    g_touchDown.reset();
    g_mouseButton.reset();
}
