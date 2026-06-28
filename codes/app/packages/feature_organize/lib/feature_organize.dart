/// Tessera ORGANIZE space (R3): the organizer dashboard, the create flow
/// with the spec §5 private defaults, the distribute sheet and the
/// run-event console — plus the relayer-backed ports the shell wires in.
library;

export 'src/console/live_host_console.dart';
export 'src/create/create_flow_view.dart';
export 'src/home/organize_home_controller.dart';
export 'src/home/organize_space_view.dart';
export 'src/home/organizer_poll_card.dart';
export 'src/module_names.dart';
export 'src/organize_copy.dart';
export 'src/ports/organize_gateway.dart';
export 'src/ports/organizer_console_port.dart';
export 'src/ports/relay_live_host_port.dart';
export 'src/ports/relay_organizer_port.dart';
export 'src/ports/server_organizer_port_adapter.dart';
export 'src/qr/qr_matrix.dart';
export 'src/qr/qr_view.dart';
export 'src/share/distribute_sheet.dart';

/// Kept from the R3 scaffold smoke test.
const String featureOrganizePackageName = 'feature_organize';
