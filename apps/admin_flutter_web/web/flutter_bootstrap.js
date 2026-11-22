{{flutter_js}}
{{flutter_build_config}}

// CanvasKit is shipped in build/web; startup does not depend on a third-party CDN.
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
