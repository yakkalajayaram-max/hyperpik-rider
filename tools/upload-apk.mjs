// Uploads a release APK to a Supabase Storage bucket under a versioned name and a stable "latest" name.
//
//   node tools/upload-apk.mjs --apk build/app/outputs/flutter-apk/app-release.apk --app rider --bucket rider-app-releases
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in the environment (GitHub Actions secrets). Node 20+, no dependencies.
// Version and build come from pubspec.yaml ("1.7.0+27"). Files written:
//   hyperpik-<app>-<version>-<build>-arm64.apk   (kept forever)
//   hyperpik-<app>-latest.apk                    (overwritten; the permanent download name)
import { readFileSync } from "node:fs";

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) args.set(process.argv[i].replace(/^--/, ""), process.argv[i + 1]);
const apk = args.get("apk");
const app = args.get("app") ?? "rider";
const bucket = args.get("bucket") ?? "rider-app-releases";
const url = (process.env.SUPABASE_URL ?? "").replace(/\/$/, "");
const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
if (!apk || !url || !key) {
  console.error("Usage: --apk <file>; SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set.");
  process.exit(1);
}
const m = readFileSync("pubspec.yaml", "utf8").match(/^version:\s*([\d.]+)\+(\d+)/m);
if (!m) {
  console.error("Could not read version from pubspec.yaml");
  process.exit(1);
}
const body = readFileSync(apk);
const names = [`hyperpik-${app}-${m[1]}-${m[2]}-arm64.apk`, `hyperpik-${app}-latest.apk`];
for (const name of names) {
  const res = await fetch(`${url}/storage/v1/object/${bucket}/${name}`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: "Bearer " + key,
      "content-type": "application/vnd.android.package-archive",
      "x-upsert": "true",
      "cache-control": "300",
    },
    body,
  });
  if (!res.ok) {
    console.error(`Upload of ${name} failed: ${res.status} ${await res.text()}`);
    process.exit(1);
  }
  console.log(`Uploaded ${name} (${body.length} bytes) to bucket ${bucket}`);
}

// OTA manifest: the installed app reads this to learn that a newer build exists (lib/core/app_update.dart).
if (args.get("manifest") === "true") {
  const { createHash } = await import("node:crypto");
  const auth = { apikey: key, Authorization: "Bearer " + key };
  let previous = {};
  const cur = await fetch(`${url}/storage/v1/object/${bucket}/manifest.json`, { headers: auth });
  if (cur.ok) previous = (await cur.json()).android ?? {};
  if (previous.build && Number(m[2]) < previous.build && args.get("force") !== "true") {
    console.error(`Refusing: build ${m[2]} is older than the published ${previous.build}.`);
    process.exit(1);
  }
  const manifest = {
    android: {
      version: m[1],
      build: Number(m[2]),
      // Keep the previous floor; lowering it by accident would let a broken build keep running.
      minBuild: args.get("min-build") !== undefined ? Number(args.get("min-build")) : (previous.minBuild ?? 0),
      path: names[0],
      sha256: createHash("sha256").update(body).digest("hex"),
      size: body.length,
      notes: args.get("notes") ?? "",
      publishedAt: new Date().toISOString(),
    },
  };
  const res = await fetch(`${url}/storage/v1/object/${bucket}/manifest.json`, {
    method: "POST",
    headers: { ...auth, "content-type": "application/json", "x-upsert": "true", "cache-control": "0" },
    body: JSON.stringify(manifest, null, 2),
  });
  if (!res.ok) {
    console.error(`Manifest upload failed: ${res.status} ${await res.text()}`);
    process.exit(1);
  }
  console.log("Manifest updated: " + names[0]);
}
