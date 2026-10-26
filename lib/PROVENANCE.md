# Vendored dependencies

Dependencies are ordinary source files, not submodules. Builds and tests require
no dependency downloads. The vendored source files are unmodified upstream files.

| Package | Pinned release | Included files | License |
| --- | --- | --- | --- |
| OpenZeppelin Contracts | v5.1.0 | ERC20, IERC20, IERC20Metadata, Context, draft-IERC6093 | MIT |
| forge-std | v1.9.7 | `src/` test utilities | MIT / Apache-2.0 |

Original release archives and SHA-256 digests:

- https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.1.0
  `8a3b08cfc756437ba3343901565b18182adb42ec1e621960240a19da5d738686`
- https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
  `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`

Licenses are included beside each dependency. `forge-std` is used only in tests.
