"""One-time setup run on Codemagic: register the probe bundle IDs and create App Store
provisioning profiles for them, using the App Store Connect API key from the integration.

Only creates resources that do not exist yet. Never deletes or revokes anything.
Profiles include every currently valid Apple Distribution certificate, so the profile works
with the certificate Codemagic stores for this app.
"""
import datetime
import json
import subprocess
import sys

ASC = "app-store-connect"


def run(*args):
    result = subprocess.run([ASC, *args, "--json"], check=True, capture_output=True, text=True)
    return json.loads(result.stdout or "null")


def ensure_bundle_id(identifier, name):
    found = run("bundle-ids", "list", "--bundle-id-identifier", identifier, "--strict-match-identifier")
    if found:
        print(f"Bundle ID exists: {identifier}")
        return found[0]["id"]
    created = run("bundle-ids", "create", identifier, "--name", name, "--platform", "IOS")
    print(f"Bundle ID created: {identifier}")
    return created["id"]


def valid_distribution_certificates():
    now = datetime.datetime.now(datetime.timezone.utc)
    ids = []
    for cert in run("certificates", "list", "--type", "DISTRIBUTION", "IOS_DISTRIBUTION"):
        attributes = cert["attributes"]
        expires = datetime.datetime.fromisoformat(attributes["expirationDate"].replace("Z", "+00:00"))
        if expires > now:
            ids.append(cert["id"])
            print(f"Distribution certificate: {attributes.get('displayName')} serial {attributes.get('serialNumber')} expires {expires.date()}")
    if not ids:
        sys.exit("No valid distribution certificate found")
    return ids


def ensure_profile(bundle_resource_id, identifier, certificate_ids):
    name = f"{identifier} AppStore probe"
    existing = [p for p in run("profiles", "list", "--type", "IOS_APP_STORE", "--name", name)
                if p["attributes"].get("profileState") == "ACTIVE"]
    if existing:
        print(f"Profile exists: {name}")
        return
    run("profiles", "create", bundle_resource_id, "--type", "IOS_APP_STORE", "--name", name,
        "--certificate-ids", *certificate_ids)
    print(f"Profile created: {name}")


def main():
    app_id = sys.argv[1]
    if app_id.startswith("com.kaitooofficial.pocketbase") or app_id.startswith("com.example."):
        sys.exit("Refusing to touch a non-probe identifier")
    certificates = valid_distribution_certificates()
    for identifier, name in [(app_id, "Workout Probe"), (f"{app_id}.activity", "Workout Probe Activity")]:
        resource_id = ensure_bundle_id(identifier, name)
        ensure_profile(resource_id, identifier, certificates)


if __name__ == "__main__":
    main()
