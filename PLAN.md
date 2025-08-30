# WSL Path Resolution Fix Plan

## Problem Summary

WSL path resolution fails with "DevServerPathDoesNotExist" error when opening projects from within WSL. The Windows client correctly converts WSL paths to UNC format (`//?\UNC/wsl.localhost/NixOS/home/nixos/documents/zed`), but the remote server cannot resolve them back to the WSL filesystem.

**Error**: `RPC Request AddWorktree failed DevServerPathDoesNotExist path=//?/UNC/wsl.localhost/NixOS/home/nixos/documents/zed`

## Root Cause Analysis

The issue occurs in this flow:
1. User runs `zed /home/nixos/documents/zed` in WSL
2. WSL wrapper calls Windows `zed.exe --wsl "nixos@NixOS" /home/nixos/documents/zed`
3. Windows client converts path to UNC format: `//?\UNC/wsl.localhost/NixOS/home/nixos/documents/zed`
4. Windows client sends AddWorktree RPC with UNC path to WSL remote server
5. **FAILURE**: Remote server receives UNC path but expects native WSL path format

## Investigation Steps

### 1. Study Path Conversion Flow
- [ ] Read `crates/remote/src/transport/wsl.rs` thoroughly
- [ ] Examine existing `windows_path_to_wsl_path` function
- [ ] Find where AddWorktree RPC requests are prepared/sent
- [ ] Trace path handling in WSL RemoteConnection implementation

### 2. Compare with SSH Implementation
- [ ] Study `crates/remote/src/transport/ssh.rs` for reference
- [ ] See how SSH handles path conversion for remote servers
- [ ] Identify differences in path handling between SSH and WSL transports

### 3. Trace Exact Failure Point
- [ ] Find where "DevServerPathDoesNotExist" error is generated
- [ ] Understand what path validation is failing in remote server
- [ ] Verify if issue is in transport layer or remote server validation

## Proposed Solution

### Location
Fix should be implemented in `crates/remote/src/transport/wsl.rs` in the RPC message preparation code.

### Implementation
Add UNC-to-WSL path conversion before sending paths to remote server:

```rust
/// Convert Windows UNC WSL path back to native WSL path
/// Converts: //?\UNC/wsl.localhost/DISTRO/path/to/file
/// To: /path/to/file
fn convert_unc_to_wsl_path(unc_path: &str) -> Option<String> {
    if let Some(stripped) = unc_path.strip_prefix("//?\UNC/wsl.localhost/") {
        // Find first slash after distro name
        if let Some(slash_pos) = stripped.find('/') {
            return Some(stripped[slash_pos..].to_string());
        }
    }
    None
}
```

### Integration Points
- [ ] Apply conversion in AddWorktree RPC preparation
- [ ] Ensure all path-related RPC messages use converted paths
- [ ] Handle edge cases (relative paths, root paths, etc.)
- [ ] Add proper error handling for invalid UNC paths

## Testing Plan

### Test Cases
1. **From WSL**: `zed /home/nixos/documents/zed` should work
2. **From Windows**: `zed.exe --wsl "nixos@NixOS" /home/nixos/documents/zed` should continue working
3. **Edge cases**: 
   - Root directory: `zed /`
   - Relative paths: `zed .` and `zed ../project`
   - Non-existent paths: proper error handling

### Verification
- [ ] Test on different WSL distributions
- [ ] Verify no regression in Windows-initiated WSL connections
- [ ] Test with various project structures and path formats

## Files to Modify

Primary:
- `crates/remote/src/transport/wsl.rs` - Add UNC path conversion logic

Secondary (if needed):
- `crates/remote/src/remote_client.rs` - RPC message preparation
- `crates/paths/src/paths.rs` - Path utilities if needed

## Success Criteria

- [ ] `zed /path/to/project` works from within WSL
- [ ] No regression in Windows-initiated WSL connections  
- [ ] Proper error messages for invalid paths
- [ ] All existing tests pass
- [ ] New tests added for WSL path conversion

## Related Code References

- Commit f78f3e7729 - Initial WSL support implementation
- `crates/remote/src/transport/ssh.rs` - Reference implementation
- `crates/remote/src/remote_client.rs` - RPC handling
- WSL wrapper script: `crates/zed/resources/windows/zed-wsl`
