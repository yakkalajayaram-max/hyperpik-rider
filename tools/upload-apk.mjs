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
