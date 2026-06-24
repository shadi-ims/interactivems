<?php
/**
 * IMS StreamPulse — stream output endpoint
 * ----------------------------------------------------------------------
 * The app calls:
 *   GET  https://interactivems.net/ims/streampulse/app/            -> instance list
 *   GET  https://interactivems.net/ims/streampulse/app/{instance}  -> that wall's streams
 *
 * JSON contract consumed by the Flutter app (lib/config.dart):
 *   index    -> { "instances": [ { "id","name","count" }, ... ] }
 *   instance -> { "instance","name", "streams": [ { "name","url" }, ... ] }
 *
 * Drop this file (and .htaccess) in the  .../ims/streampulse/app/  directory.
 * Edit $BASE_PATH below if you deploy under a different path.
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Cache-Control: no-store');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

// Path this script is mounted under (no trailing slash).
const BASE_PATH = '/ims/streampulse/app';

/* ======================================================================
 *  STREAM LIBRARY  — edit this to add channels / walls.
 *  Each instance = a wall: a name + an ordered list of streams.
 *  The app's 2 / 4 / 6 selector decides how many of these it shows.
 * ====================================================================== */

$HOST = 'https://wd-stream11.widekhaliji.com:8446';

// helper: build a stream entry from a path on the default host
$s = function (string $name, string $path) use ($HOST): array {
    return ['name' => $name, 'url' => $HOST . $path];
};

$INSTANCES = [

    // default wall (4 streams)
    'default' => [
        'name'    => 'Main Wall',
        'streams' => [
            $s('Al Mashhad', '/almashhad/abr_live/playlist.m3u8'),
            $s('Al Sharq',   '/alsharq/abr_live/playlist.m3u8'),
            $s('Al Arabia',  '/alarabia/abr_live/playlist.m3u8'),
            $s('Al Hadath',  '/alhadath/abr_live/playlist.m3u8'),
        ],
    ],

    // 2-up wall
    'duo' => [
        'name'    => 'Duo',
        'streams' => [
            $s('Al Mashhad', '/almashhad/abr_live/playlist.m3u8'),
            $s('Al Hadath',  '/alhadath/abr_live/playlist.m3u8'),
        ],
    ],

    // 6-up wall — replace the last two with your real channels
    'newsroom' => [
        'name'    => 'Newsroom',
        'streams' => [
            $s('Al Mashhad', '/almashhad/abr_live/playlist.m3u8'),
            $s('Al Sharq',   '/alsharq/abr_live/playlist.m3u8'),
            $s('Al Arabia',  '/alarabia/abr_live/playlist.m3u8'),
            $s('Al Hadath',  '/alhadath/abr_live/playlist.m3u8'),
            $s('Channel 5',  '/channel5/abr_live/playlist.m3u8'),
            $s('Channel 6',  '/channel6/abr_live/playlist.m3u8'),
        ],
    ],
];

/* ======================================================================
 *  ROUTING  — figure out which instance was requested.
 * ====================================================================== */

function resolve_instance(): string {
    // 1) explicit ?i= fallback (works without URL rewriting)
    if (isset($_GET['i'])) return (string) $_GET['i'];

    // 2) strip BASE_PATH from the request URI, take the first real segment.
    //    Robust across Apache rewrite, PATH_INFO and dev-server setups.
    $path = rawurldecode(parse_url($_SERVER['REQUEST_URI'] ?? '', PHP_URL_PATH) ?? '');
    $pos  = strpos($path, BASE_PATH);
    $rest = ($pos !== false) ? substr($path, $pos + strlen(BASE_PATH)) : $path;

    foreach (explode('/', trim($rest, '/')) as $seg) {
        if ($seg !== '' && $seg !== 'index.php') return $seg;
    }
    return '';
}

function out(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
    exit;
}

// sanitize: instance ids are limited to safe characters
$instance = preg_replace('/[^A-Za-z0-9_\-]/', '', resolve_instance());

/* ----- index: list of available walls --------------------------------- */
if ($instance === '') {
    $list = [];
    foreach ($INSTANCES as $id => $cfg) {
        $list[] = [
            'id'    => $id,
            'name'  => $cfg['name'],
            'count' => count($cfg['streams']),
        ];
    }
    out(['instances' => $list]);
}

/* ----- a single wall -------------------------------------------------- */
if (!isset($INSTANCES[$instance])) {
    out(['error' => 'unknown instance', 'instance' => $instance], 404);
}

$cfg = $INSTANCES[$instance];
out([
    'instance' => $instance,
    'name'     => $cfg['name'],
    'streams'  => array_values($cfg['streams']),
]);
