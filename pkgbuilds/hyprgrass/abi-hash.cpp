// Prints the plugin ABI string for the installed Hyprland headers: the value
// a running Hyprland reports as abiHash in `hyprctl version -j`. Copy of
// __hyprland_api_get_client_hash() in src/plugins/PluginAPI.hpp, built from
// version.h alone (PluginAPI.hpp needs symbols only Hyprland itself has).
// The PKGBUILD checks that the upstream format string is still this one.
#include <hyprland/src/version.h>
#include <format>
#include <iostream>
#include <string>
#include <string_view>

static std::string stripPatch(const char* ver) {
    std::string_view v = ver;
    if (!v.contains('.'))
        return std::string{v};
    return std::string{v.substr(0, v.find_last_of('.'))};
}

int main() {
    std::cout << std::format("{}_aq_{}_hu_{}_hg_{}_hc_{}_hlg_{}", GIT_COMMIT_HASH, stripPatch(AQUAMARINE_VERSION),
                             stripPatch(HYPRUTILS_VERSION), stripPatch(HYPRGRAPHICS_VERSION),
                             stripPatch(HYPRCURSOR_VERSION), stripPatch(HYPRLANG_VERSION))
              << '\n';
}
