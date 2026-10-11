"""Real CMake/ccache regression in the production local-toolchain container.

Run: python3 tests/test_incremental.py TOOLCHAIN_IMAGE
The fixture has no external network and never touches a realm or database.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

IMAGE = sys.argv.pop(1)
SCRIPT = Path(__file__).resolve().parents[1] / 'docker/build-incremental.sh'


class IncrementalBuildTest(unittest.TestCase):
    def test_objects_headers_revisions_submodules_and_failed_compile(self):
        with tempfile.TemporaryDirectory(prefix='turtlewow-build-test-') as temp:
            root = Path(temp)
            source, cache = root / 'source', root / 'cache'
            source.mkdir()
            cache.mkdir()

            def git(*args):
                return subprocess.check_output(['git', '-C', str(source), *args], text=True).strip()

            git('init')
            git('config', 'user.email', 'test@example.invalid')
            git('config', 'user.name', 'Build Regression')
            (source / 'CMakeLists.txt').write_text('''cmake_minimum_required(VERSION 3.16)
project(incremental_fixture LANGUAGES CXX)
add_executable(fixture main.cpp helper.cpp)
install(TARGETS fixture DESTINATION bin)
''')
            (source / 'shared.h').write_text('#define RESULT 0\n')
            (source / 'main.cpp').write_text('#include "shared.h"\nint helper(); int main() {return helper()+RESULT;}\n')
            (source / 'helper.cpp').write_text('#include "shared.h"\nint helper() {return RESULT;}\n')
            (source / 'sql/base').mkdir(parents=True)
            (source / 'sql/database_updates').mkdir()
            (source / 'sql/character_updates').mkdir()
            for leaf in ['create_databases.sql', 'base/test.sql', 'database_updates/test.sql', 'character_updates/test.sql']:
                (source / 'sql' / leaf).write_text('-- fixture\n')
            # Same local submodule layout as the game checkout, available offline.
            sub = root / 'sub'
            sub.mkdir()
            subprocess.run(['git', 'init', str(sub)], check=True, capture_output=True)
            subprocess.run(['git', '-C', str(sub), 'config', 'user.email', 'test@example.invalid'], check=True)
            subprocess.run(['git', '-C', str(sub), 'config', 'user.name', 'Build Regression'], check=True)
            (sub / 'marker').write_text('submodule\n')
            subprocess.run(['git', '-C', str(sub), 'add', '.'], check=True)
            subprocess.run(['git', '-C', str(sub), 'commit', '-m', 'fixture'], check=True, capture_output=True)
            git('-c', 'protocol.file.allow=always', 'submodule', 'add', str(sub), 'src/modules/Eluna')

            def commit(message):
                git('add', '.')
                git('commit', '-m', message)
                return git('rev-parse', 'HEAD')

            def build(revision, success=True):
                args = ['docker', 'run', '--rm', '--network', 'none',
                        '--mount', f'type=bind,src={source},dst=/local-core,readonly',
                        '--mount', f'type=bind,src={cache},dst=/native-cache',
                        '--mount', f'type=bind,src={SCRIPT},dst=/build.sh,readonly']
                for key, value in {'SOURCE_COMMIT': revision, 'CPU_TARGET': 'x86-64-v2', 'BUILD_JOBS': '2',
                                   'CMAKE_BUILD_TYPE': 'Release', 'CMAKE_INSTALL_PREFIX': '/opt/turtle',
                                   'BUILD_PLAYERBOTS': 'OFF', 'USE_EXTRACTORS': 'OFF'}.items():
                    args += ['-e', f'{key}={value}']
                result = subprocess.run(args + [IMAGE, 'bash', '-c',
                    'trap "chmod -R a+rwX /native-cache" EXIT; bash /build.sh && cat /opt/turtle/SOURCE_COMMIT'], text=True, capture_output=True)
                if success:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                    self.assertEqual(result.stdout.splitlines()[-1], revision)
                else:
                    self.assertNotEqual(result.returncode, 0)
                return result

            def objects():
                return {p.name: p.stat().st_mtime_ns for p in (cache / 'build').rglob('*.cpp.o')}

            first = commit('first')
            build(first)
            original = objects()
            self.assertEqual(set(original), {'main.cpp.o', 'helper.cpp.o'})
            build(first)
            self.assertEqual(objects(), original, 'Same revision must retain objects')
            (source / 'README.md').write_text('Documentation-only change\n')
            docs = commit('docs')
            build(docs)
            self.assertEqual(objects(), original, 'Documentation must not recompile C++')
            (source / 'helper.cpp').write_text('#include "shared.h"\nint helper() {return RESULT+1;}\n')
            changed = commit('one source')
            build(changed)
            one = objects()
            self.assertEqual(one['main.cpp.o'], original['main.cpp.o'])
            self.assertNotEqual(one['helper.cpp.o'], original['helper.cpp.o'])
            (source / 'shared.h').write_text('#define RESULT 2\n')
            headers = commit('shared header')
            build(headers)
            both = objects()
            self.assertTrue(all(both[name] != one[name] for name in both))
            # Explicit older revisions do not move or edit the input checkout.
            build(first)
            self.assertEqual(git('rev-parse', 'HEAD'), headers)
            self.assertEqual(git('status', '--porcelain'), '')
            (source / 'helper.cpp').write_text('THIS IS NOT VALID C++\n')
            broken = commit('broken')
            failure = build(broken, success=False)
            self.assertIn('error:', failure.stderr)
            build('f' * 40, success=False)
            print(json.dumps({'same_revision': 'retained', 'docs_only': 'retained',
                'one_cpp': 'one_object', 'shared_header': 'both_objects',
                'older_revision': 'verified', 'failed_compile': 'rejected',
                'missing_revision': 'rejected', 'submodule': 'offline'}))
            # Docker creates root-owned fixture files; remove only this exact
            # temporary cache through the same isolated container before cleanup.
            subprocess.run(['docker', 'run', '--rm', '--network', 'none', '--mount',
                f'type=bind,src={cache},dst=/fixture-cache', IMAGE,
                'bash', '-c', 'find /fixture-cache -mindepth 1 -delete'], check=True)


if __name__ == '__main__':
    unittest.main()
