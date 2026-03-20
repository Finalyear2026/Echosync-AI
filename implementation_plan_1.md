# Model Registry Sync Implementation Plan

Improve the model registry management by transitioning from a purely in-memory cloud fetch to a persistent local cache synced with GitHub.

## Proposed Changes

### [Core Services]

#### [MODIFY] [model_manager_service.dart](file:///e:/current_work/project/echosync_ai/lib/services/model_manager_service.dart)
- **GitHub URL**: Update `registryDriveId` (or rename to `registryUrl`) to use the raw GitHub URL.
- **Local Registry Storage**: 
    - Implement `getLocalRegistryFile()` to get the reference to [models.json](file:///e:/current_work/project/echosync_ai/models.json) on disk.
    - Implement `ensureLocalRegistryExists()` to copy from [assets/models.json](file:///e:/current_work/project/echosync_ai/assets/models.json) if the file doesn't exist.
- **ETag Sync**:
    - Update [fetchCloudRegistry](file:///e:/current_work/project/echosync_ai/lib/services/model_manager_service.dart#23-51) to use `Dio` with `If-None-Match` header.
    - Implement `syncRegistryWithCloud()` that handles 304 (use local) vs 200 (update local & ETag).
    - Use "Atomic Swap": Download to `.tmp` file, then rename to ensure no corruption.

#### [MODIFY] [settings_service.dart](file:///e:/current_work/project/echosync_ai/lib/services/settings_service.dart)
- **ETag Persistence**: Add methods to store and retrieve the `registry_etag` in the `settings` box.

### [State Management]

#### [MODIFY] [app_provider.dart](file:///e:/current_work/project/echosync_ai/lib/providers/app_provider.dart)
- **Initialization**: 
    - First, load the registry from [models.json](file:///e:/current_work/project/echosync_ai/models.json) on disk to populate `_cloudCategories` immediately.
    - Then, fire off the `syncRegistryWithCloud()` in the background if online.
- **Sync Integration**: Refresh statuses and UI if the sync results in a new version.

### [UI Components]

#### [MODIFY] [models_screen.dart](file:///e:/current_work/project/echosync_ai/lib/screens/models_screen.dart)
- **Offline Logic**:
    - Grey out "Download" and "Resume" buttons when offline.
    - Add logic to show a `SnackBar` reminder when clicking disabled buttons.

---

## Verification Plan

### Automated Tests/Checks
- Check that the `assets` folder exists and contains [models.json](file:///e:/current_work/project/echosync_ai/models.json).
- Verify [pubspec.yaml](file:///e:/current_work/project/echosync_ai/pubspec.yaml) contains the [assets/models.json](file:///e:/current_work/project/echosync_ai/assets/models.json) entry.

### Manual Verification
1.  **First Launch**: Delete the app data, start the app offline. Confirm "Models" screen shows the fallback models from the asset.
2.  **Background Sync**: Start app online. Confirm it fetches from GitHub.
3.  **ETag Check**: Re-open the models screen online. Verify (via logs) that it receives a **304 Not Modified**.
4.  **Offline UI**: Turn off internet. Confirm buttons are greyed out and clicking them shows a SnackBar.
5.  **Corrupt Recovery**: Manually delete [models.json](file:///e:/current_work/project/echosync_ai/models.json) from the phone. Confirm the app re-copies it from the assets on the next launch.
