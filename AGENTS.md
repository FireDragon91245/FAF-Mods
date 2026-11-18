# Local testing workflow

- After changes are built, validated, and ready for in-game testing, install the latest affected mod packages into FAF's configured mods directory. The user explicitly wants installation included, without a separate confirmation.
- Include the shared FireDragon Mod Loader when its package or a required dependency changes. Use its ownership-aware installer for the native loader/bootstrap.
- Verify installed versions and package file hashes after installation, and remove obsolete mod files when updating packaged mods.
- Do not change installed files while Forged Alliance is running or terminate the user's game. If it is running, report that it must be closed before installation can finish.

# User communication preferences

- Change code, files, or settings only when the user asks for a change or clearly authorizes that work.
- Treat explanations, reasoning, corrections of understanding, and questions as discussion, not as implicit requests to modify anything.
- In an ongoing task, a user's explanation of why an approach is right or wrong does not itself authorize another implementation change.
- If it is unclear whether the user wants a change or is explaining or asking a question, ask before making changes. Do not assume.
