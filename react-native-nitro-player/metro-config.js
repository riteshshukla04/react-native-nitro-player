const fs = require('fs')
const path = require('path')

function escapeRegExp(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

/**
 * Wraps a Metro config to support local development linking of react-native-nitro-player.
 *
 * Usage in metro.config.js:
 *   const { wrapWithNitroPlayer } = require('react-native-nitro-player/metro-config')
 *   module.exports = wrapWithNitroPlayer(config)
 *
 * This is only needed when the package is symlinked (e.g. via `bun link`).
 * Published/installed packages work without this.
 */
function wrapWithNitroPlayer(config) {
  // Resolve the real path of this package on disk, following any symlinks.
  // __dirname may point to the symlink location; realpathSync gives the source.
  const packageRoot = fs.realpathSync(path.resolve(__dirname))

  config.resolver = config.resolver ?? {}
  // Tell Metro to follow symlinks in node_modules
  config.resolver.unstable_enableSymlinks = true

  // When Metro resolves imports from within the linked package's source tree,
  // it must look up dependencies in the consuming project's node_modules —
  // not the package's own (which won't have react-native, nitro-modules, etc.)
  // config.projectRoot is set by getDefaultConfig(__dirname) to the app root.
  const projectNodeModules = path.join(config.projectRoot, 'node_modules')
  const existing = config.resolver.nodeModulesPaths ?? []
  if (!existing.includes(projectNodeModules)) {
    config.resolver.nodeModulesPaths = [...existing, projectNodeModules]
  }

  // Pin peer dependencies to the consuming project's copies.
  // Without this, Metro finds react-native inside the package's own node_modules
  // first (since it's closer in the directory tree), causing a split-instance crash
  // where platform internals like PlatformConstants can't be found.
  // extraNodeModules overrides resolution regardless of the importing file's location.
  const peerDeps = [
    'react',
    'react-native',
    'react-native-nitro-modules',
  ]
  const extraNodeModules = config.resolver.extraNodeModules ?? {}
  for (const dep of peerDeps) {
    if (!extraNodeModules[dep]) {
      const resolved = path.join(projectNodeModules, dep)
      if (fs.existsSync(resolved)) {
        extraNodeModules[dep] = resolved
      }
    }
  }
  config.resolver.extraNodeModules = extraNodeModules

  // Block Metro from loading peer deps out of the linked package's own node_modules.
  // extraNodeModules alone isn't enough — Metro's hierarchical resolver finds the
  // closer copy first when the importing file lives inside the package tree.
  // blockList wins unconditionally, forcing Metro up to the project's node_modules.
  const packageNodeModules = path.join(packageRoot, 'node_modules')
  const blockPatterns = peerDeps.map(
    (dep) => new RegExp(`^${escapeRegExp(path.join(packageNodeModules, dep))}.*`)
  )
  const existingBlockList = config.resolver.blockList
  const existingPatterns = existingBlockList
    ? Array.isArray(existingBlockList)
      ? existingBlockList
      : [existingBlockList]
    : []
  config.resolver.blockList = [...existingPatterns, ...blockPatterns]

  // Add the real package root to watchFolders so Metro indexes it
  const existingWatchFolders = config.watchFolders ?? []
  if (!existingWatchFolders.includes(packageRoot)) {
    config.watchFolders = [...existingWatchFolders, packageRoot]
  }

  return config
}

module.exports = { wrapWithNitroPlayer }
