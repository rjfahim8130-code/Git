# GitHub Zip Pusher

Personal mobile tool: multi GitHub PAT, pick repo/branch, one-click ZIP push (single commit), browse & bulk delete.

## Setup
1. `flutter pub get`
2. `flutter run`
3. Settings → add GitHub Personal Access Token (`repo` scope or Contents read/write)
4. Select repo → Upload ZIP → Commit & Push

No backend. Tokens stored with flutter_secure_storage only on device.
