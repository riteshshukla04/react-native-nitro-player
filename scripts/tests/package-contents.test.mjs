/* eslint-env es2020, node */
import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { after, test } from 'node:test'
import { fileURLToPath } from 'node:url'

const root = fileURLToPath(new URL('../../', import.meta.url))
const packageRoot = join(root, 'react-native-nitro-player')
const temporary = mkdtempSync(join(tmpdir(), 'nitro-package-test-'))
after(() => rmSync(temporary, { recursive: true, force: true }))
const [packed] = JSON.parse(
  execFileSync(
    'npm',
    ['pack', '--ignore-scripts', '--json', '--pack-destination', temporary],
    {
      cwd: packageRoot,
      encoding: 'utf8',
    }
  )
)
const archive = join(temporary, packed.filename)
const entries = new Set(
  execFileSync('tar', ['-tf', archive], { encoding: 'utf8' }).trim().split('\n')
)
const archived = path =>
  execFileSync('tar', ['-xOf', archive, `package/${path}`], {
    encoding: 'utf8',
  })

test('every consumer rules file declared by the published Gradle build exists in the archive', () => {
  const gradle = archived('android/build.gradle')
  const declarations = [...gradle.matchAll(/consumerProguardFiles\s+([^\n]+)/g)]
  assert.ok(
    declarations.length > 0,
    'expected the library to declare consumer rules'
  )
  for (const declaration of declarations) {
    for (const [, path] of declaration[1].matchAll(/["']([^"']+)["']/g)) {
      assert.ok(
        entries.has(`package/android/${path}`),
        `published Gradle build references missing ${path}`
      )
    }
  }
})

test('published rules retain their complete source contents, including Cast reflection rules', () => {
  const path = 'android/consumer-rules.pro'
  assert.equal(archived(path), readFileSync(join(packageRoot, path), 'utf8'))
  assert.match(archived(path), /NitroCastOptionsProvider/)
})
