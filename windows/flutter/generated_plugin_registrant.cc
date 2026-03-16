//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <local_notifier/local_notifier_plugin.h>
#include <nsd_windows/nsd_windows_plugin_c_api.h>

void RegisterPlugins(flutter::PluginRegistry* registry) {
  LocalNotifierPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("LocalNotifierPlugin"));
  NsdWindowsPluginCApiRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("NsdWindowsPluginCApi"));
}
