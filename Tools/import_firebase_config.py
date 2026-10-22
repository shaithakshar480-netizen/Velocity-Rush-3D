"""Source-only client-config import. Never prints client keys or OAuth payloads."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'Config/Firebase/google-services.json'
TARGET = ROOT / 'Data/FirebaseConfig.json'

def main():
    supplied = json.loads(SOURCE.read_text())
    clients = [item for item in supplied['client']
               if item['client_info']['android_client_info']['package_name'] == 'com.velocityrush3d.game']
    if len(clients) != 1 or supplied['project_info']['project_id'] != 'velocity-rush-3d':
        raise ValueError('Firebase project/package mismatch')
    client = clients[0]
    oauth = client['oauth_client']
    web = next(item['client_id'] for item in oauth if item['client_type'] == 3)
    android = next(item['client_id'] for item in oauth if item['client_type'] == 1)
    current = json.loads(TARGET.read_text())
    current.update(configured=True,
        firebase_project_id=supplied['project_info']['project_id'],
        firebase_project_number=supplied['project_info']['project_number'],
        firebase_app_id=client['client_info']['mobilesdk_app_id'],
        firebase_api_key=client['api_key'][0]['current_key'],
        android_package_name='com.velocityrush3d.game',
        storage_bucket=supplied['project_info']['storage_bucket'],
        android_oauth_client_id=android, web_client_id=web)
    TARGET.write_text(json.dumps(current, indent=2) + '\n')
    print('Firebase client configuration imported; no credentials logged.')

if __name__ == '__main__':
    main()
