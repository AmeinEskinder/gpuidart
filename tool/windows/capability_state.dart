String capabilityInstallStatus(
  List<Map<String, dynamic>> capabilities,
  bool restartNeeded,
) {
  final states = capabilities.map((entry) => entry['State']).toList();
  if (states.isEmpty ||
      states.any(
        (state) =>
            !['Installed', 'InstallPending', 'NotPresent'].contains(state),
      )) {
    return 'incomplete';
  }
  if (restartNeeded || states.contains('InstallPending')) {
    return 'restart_required';
  }
  return states.every((state) => state == 'Installed')
      ? 'installed'
      : 'incomplete';
}
