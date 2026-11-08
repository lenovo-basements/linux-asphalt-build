import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';
import Clutter from 'gi://Clutter';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';

// The motors sit at the two short ends of the panel: "left" at the top end in
// portrait (camera side), "right" at the bottom end.
const LEFT_DEV = '/sys/bus/i2c/devices/11-005a';
const RIGHT_DEV = '/sys/bus/i2c/devices/13-005a';
const BUILTIN_CONNECTOR = 'DSI-1';
const CHARGE_BEHAVIOUR_PATH = '/sys/class/power_supply/qcom-battmgr-bat/charge_behaviour';
const CHARGE_HELPER = '/usr/local/bin/y700-bypass-charge';
const CHARGER_ONLINE_PATH = '/sys/class/power_supply/qcom-battmgr-usb/online';
const BYPASS_STATE_PATH = '/var/lib/y700/bypass-charge';

function readText(path) {
    try {
        const [ok, contents] = Gio.File.new_for_path(path).load_contents(null);
        return ok ? new TextDecoder().decode(contents).trim() : null;
    } catch (e) {
        // Missing file, or ENODATA from charge_behaviour after a firmware restart.
        return null;
    }
}

function writeSysfs(path, str) {
    try {
        const file = Gio.File.new_for_path(path);
        const stream = file.append_to(Gio.FileCreateFlags.NONE, null);
        stream.write(str, null);
        stream.close(null);
    } catch (e) {
        // ignore sysfs write errors
    }
}

function pulseMotor(dev) {
    writeSysfs(`${dev}/activate`, '0');
    writeSysfs(`${dev}/level`, '140');
    writeSysfs(`${dev}/index`, '1');
    writeSysfs(`${dev}/duration`, '30');
    writeSysfs(`${dev}/activate`, '1');
}

function patchBrightnessManager() {
    if (!Main.brightnessManager)
        return;

    const bm = Main.brightnessManager;
    if (bm._y700Patched)
        return;

    bm._y700Patched = true;

    // Fix: DSI panels return null for vendor/product/serial which crashes GLib.Variant('a(sssssd)')
    bm._setState = function(values) {
        const tuple = new GLib.Variant('a(sssssd)', [...values].map(value => {
            const {id, brightness} = value;
            const tupleData = id.toTuple().map(s => (s === null || s === undefined) ? '' : String(s));
            return [...tupleData, brightness];
        }));
        global.set_persistent_state('brightnesses', tuple);
    };

    bm._getSavedBrightnesses = function(monitors) {
        const map = new Map();
        const saved = this._getState();

        for (const logicalMonitor of monitors) {
            const monitor = logicalMonitor.get_monitors()[0];
            const connector = monitor ? (monitor.get_connector() ?? '') : '';
            const match = saved.find(s => {
                if (!s.id) return false;
                const c = s.id._connector ?? '';
                return c === connector;
            });
            map.set(logicalMonitor, match ? match.brightness : -1.0);
        }

        return map;
    };
    console.log('[Y700] Patched Main.brightnessManager for embedded DSI panel');
}

const AutoBrightnessToggle = GObject.registerClass(
class AutoBrightnessToggle extends QuickSettings.QuickToggle {
    _init() {
        super._init({
            title: 'Auto Brightness',
            iconName: 'display-brightness-symbolic',
            toggleMode: true,
        });

        this._settings = new Gio.Settings({
            schema_id: 'org.gnome.settings-daemon.plugins.power',
        });

        this._settings.bind(
            'ambient-enabled',
            this,
            'checked',
            Gio.SettingsBindFlags.DEFAULT
        );
    }

    destroy() {
        this._settings = null;
        super.destroy();
    }
});

const BypassChargingToggle = GObject.registerClass(
class BypassChargingToggle extends QuickSettings.QuickToggle {
    _init() {
        super._init({
            title: 'Bypass Charging',
            iconName: 'battery-charging-symbolic',
            // Only acknowledged readback changes the checked state.
            toggleMode: false,
        });
        this._destroyed = false;
        this._busy = false;
        this._cancellable = new Gio.Cancellable();
        this.connect('clicked', () => this._requestPolicy());
        this._readState();
        // sysfs attributes do not reliably emit file-monitor notifications.
        this._refreshId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 5, () => {
            if (!this._busy)
                this._readState();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _readState() {
        if (this._destroyed)
            return;
        this.visible = Gio.File.new_for_path(CHARGE_BEHAVIOUR_PATH).query_exists(null);
        const policy = readText(CHARGE_BEHAVIOUR_PATH)
            ?.match(/(?:^|\s)\[(auto|inhibit-charge)\](?:\s|$)/)?.[1] ?? null;
        const pluggedIn = readText(CHARGER_ONLINE_PATH) === '1';
        this.checked = readText(BYPASS_STATE_PATH) === 'on';
        if (!this.checked)
            this.subtitle = 'Off';
        else if (policy !== 'inhibit-charge')
            this.subtitle = 'Re-applying…';
        else
            this.subtitle = pluggedIn ? 'Running on charger' : 'Waiting for charger';
        this.iconName = this.checked
            ? 'battery-level-80-plugged-in-symbolic' : 'battery-charging-symbolic';
    }

    async _requestPolicy() {
        if (this._busy || this._destroyed)
            return;
        // Re-read in case another client changed it since the last poll.
        this._readState();
        if (!this.visible)
            return;
        const command = this.checked ? 'disable' : 'enable';
        this._busy = true;
        this.reactive = false;
        this.subtitle = 'Requesting…';
        try {
            const proc = Gio.Subprocess.new(
                ['/usr/bin/pkexec', CHARGE_HELPER, command],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_PIPE);
            const [, stderr] = await new Promise((resolve, reject) => {
                proc.communicate_utf8_async(null, this._cancellable, (process, result) => {
                    try {
                        const [, stdout, error] = process.communicate_utf8_finish(result);
                        resolve([stdout, error]);
                    } catch (e) {
                        reject(e);
                    }
                });
            });
            if (!proc.get_successful())
                throw new Error(stderr.trim() || 'Authorization or charging request failed.');
        } catch (e) {
            if (!this._destroyed) {
                console.warn('[Y700] Charging policy request failed:', e.message);
                Main.notifyError('Charging request failed', e.message);
            }
        } finally {
            if (!this._destroyed) {
                this._busy = false;
                this.reactive = true;
                this._readState();
            }
        }
    }

    destroy() {
        this._destroyed = true;
        if (this._refreshId) {
            GLib.Source.remove(this._refreshId);
            this._refreshId = 0;
        }
        this._cancellable.cancel();
        super.destroy();
    }
});

const Y700QuickSettingsIndicator = GObject.registerClass(
class Y700QuickSettingsIndicator extends QuickSettings.SystemIndicator {
    _init() {
        super._init();
        this._brightToggle = new AutoBrightnessToggle();
        this._bypassToggle = new BypassChargingToggle();
        this.quickSettingsItems.push(this._brightToggle);
        this.quickSettingsItems.push(this._bypassToggle);
    }

    destroy() {
        if (this._brightToggle) {
            this._brightToggle.destroy();
            this._brightToggle = null;
        }
        if (this._bypassToggle) {
            this._bypassToggle.destroy();
            this._bypassToggle = null;
        }
        super.destroy();
    }
});

export default class Y700Extension extends Extension {
    enable() {
        patchBrightnessManager();

        // 1. Quick Settings Toggles (Auto-Brightness, Bypass Charging)
        try {
            const quickSettings = Main.panel.statusArea.quickSettings;
            if (quickSettings) {
                this._indicator = new Y700QuickSettingsIndicator();
                quickSettings.addExternalIndicator(this._indicator, 1);
                console.log('[Y700] Added Auto-Brightness and Bypass Charging QuickToggles');
            }
        } catch (e) {
            console.warn('[Y700] Failed to add QuickSettings toggles:', e.message);
        }

        // 2. Haptic OSK Feedback
        this._eventHandlerId = 0;
        const kbBox = Main.layoutManager.keyboardBox;
        if (kbBox) {
            this._eventHandlerId = kbBox.connect('captured-event', (actor, event) => {
                const type = event.type();
                if (type === Clutter.EventType.BUTTON_PRESS || type === Clutter.EventType.TOUCH_BEGIN)
                    this._keyHaptic(...event.get_coords());
                return Clutter.EVENT_PROPAGATE;
            });
        }
        this._transform = 0;
        this._monitorsChangedId = global.backend.get_monitor_manager().connect(
            'monitors-changed', () => this._updateTransform());
        this._updateTransform();

        console.log('[Y700] Extension enabled successfully');
    }

    // Position of (x, y) along the motor axis: 0 = top end in portrait (left
    // motor), 1 = bottom end (right motor). Transforms are mutter's
    // counter-clockwise rotations; 3 is landscape with the camera on the left.
    _motorAxisPosition(x, y) {
        const monitor = Main.layoutManager.keyboardMonitor ?? Main.layoutManager.primaryMonitor;
        if (!monitor)
            return 0.5;
        const fx = (x - monitor.x) / monitor.width;
        const fy = (y - monitor.y) / monitor.height;
        switch (this._transform) {
        case 1: return 1 - fx;
        case 2: return 1 - fy;
        case 3: return fx;
        default: return fy;
        }
    }

    _keyHaptic(x, y) {
        const pos = this._motorAxisPosition(x, y);
        if (pos < 0.38) {
            pulseMotor(LEFT_DEV);
        } else if (pos > 0.62) {
            pulseMotor(RIGHT_DEV);
        } else {
            pulseMotor(LEFT_DEV);
            pulseMotor(RIGHT_DEV);
        }
    }

    _updateTransform() {
        Gio.DBus.session.call('org.gnome.Mutter.DisplayConfig',
            '/org/gnome/Mutter/DisplayConfig', 'org.gnome.Mutter.DisplayConfig',
            'GetCurrentState', null, null, Gio.DBusCallFlags.NONE, -1, null,
            (conn, res) => {
                try {
                    const [, , logicalMonitors] = conn.call_finish(res).deepUnpack();
                    // (x, y, scale, transform, primary, [(connector, vendor, product, serial)], props)
                    const builtin = logicalMonitors.find(lm =>
                        lm[5].some(mon => mon[0] === BUILTIN_CONNECTOR));
                    if (builtin)
                        this._transform = builtin[3];
                } catch (e) {
                    console.warn('[Y700] Failed to read display transform:', e.message);
                }
            });
    }

    disable() {
        if (this._indicator) {
            this._indicator.destroy();
            this._indicator = null;
        }

        if (this._monitorsChangedId) {
            global.backend.get_monitor_manager().disconnect(this._monitorsChangedId);
            this._monitorsChangedId = 0;
        }

        const kbBox = Main.layoutManager.keyboardBox;
        if (kbBox && this._eventHandlerId) {
            kbBox.disconnect(this._eventHandlerId);
            this._eventHandlerId = 0;
        }

        console.log('[Y700] Extension disabled');
    }
}
