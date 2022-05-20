load(
    "@rules_erlang//:erlang_app_info.bzl",
    "ErlangAppInfo",
)
load(
    "@rules_erlang//:util.bzl",
    "path_join",
    "windows_path",
)
load(
    "@rules_erlang//private:util.bzl",
    "erl_libs_contents",
)
load(
    "//bazel/elixir:elixir_toolchain.bzl",
    "elixir_dirs",
    "erlang_dirs",
    "maybe_symlink_erlang",
)

def _impl(ctx):
    erl_libs_dir = ctx.label.name + "_deps"

    erl_libs_files = erl_libs_contents(ctx, headers = True, dir = erl_libs_dir)

    package_dir = path_join(ctx.label.workspace_root, ctx.label.package)

    erl_libs_path = path_join(package_dir, erl_libs_dir)

    (erlang_home, _, erlang_runfiles) = erlang_dirs(ctx)
    (elixir_home, elixir_runfiles) = elixir_dirs(ctx)

    if not ctx.attr.is_windows:
        output = ctx.actions.declare_file(ctx.label.name)
        script = """set -euo pipefail

export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

export PATH="{elixir_home}"/bin:"{erlang_home}"/bin:${{PATH}}

INITIAL_DIR=${{PWD}}

ln -s ${{PWD}}/{package_dir}/config ${{TEST_UNDECLARED_OUTPUTS_DIR}}
# ln -s ${{PWD}}/{package_dir}/include ${{TEST_UNDECLARED_OUTPUTS_DIR}}
ln -s ${{PWD}}/{package_dir}/lib ${{TEST_UNDECLARED_OUTPUTS_DIR}}
ln -s ${{PWD}}/{package_dir}/test ${{TEST_UNDECLARED_OUTPUTS_DIR}}
ln -s ${{PWD}}/{package_dir}/mix.exs ${{TEST_UNDECLARED_OUTPUTS_DIR}}

cd ${{TEST_UNDECLARED_OUTPUTS_DIR}}

export HOME=${{PWD}}
export DEPS_DIR=$TEST_SRCDIR/$TEST_WORKSPACE/{erl_libs_path}
export ERL_COMPILER_OPTIONS=deterministic
export MIX_ENV=test mix dialyzer
"{elixir_home}"/bin/mix local.hex --force
"{elixir_home}"/bin/mix local.rebar --force
"{elixir_home}"/bin/mix make_all

# due to https://github.com/elixir-lang/elixir/issues/7699 we
# "run" the tests, but skip them all, in order to trigger
# compilation of all *_test.exs files before we actually run them
"{elixir_home}"/bin/mix test --exclude test

export TEST_TMPDIR=${{TEST_UNDECLARED_OUTPUTS_DIR}}

# we need a running broker with certain plugins for this to pass 
trap 'catch $?' EXIT
catch() {{
    pid=$(cat ${{TEST_TMPDIR}}/*/*.pid)
    kill -TERM "${{pid}}"
}}
cd ${{INITIAL_DIR}}
./{rabbitmq_run_cmd} start-background-broker
cd ${{TEST_UNDECLARED_OUTPUTS_DIR}}

# The test cases will need to be able to load code from the deps
# directly, so we set ERL_LIBS
export ERL_LIBS=$DEPS_DIR

# run the actual tests
set +u
set -x
"{elixir_home}"/bin/mix test --trace --max-failures 1 ${{TEST_FILE}}
    """.format(
            erlang_home = erlang_home,
            elixir_home = elixir_home,
            package_dir = package_dir,
            erl_libs_path = erl_libs_path,
            rabbitmq_run_cmd = ctx.attr.rabbitmq_run[DefaultInfo].files_to_run.executable.short_path,
        )
    else:
        output = ctx.actions.declare_file(ctx.label.name + ".bat")
        script = """@echo off
echo Erlang Version: {erlang_version}

:: set LANG="en_US.UTF-8"
:: set LC_ALL="en_US.UTF-8"

set PATH="{elixir_home}\\bin";"{erlang_home}\\bin";%PATH%

set OUTPUTS_DIR=%TEST_UNDECLARED_OUTPUTS_DIR:/=\\%

:: robocopy exits non-zero when files are copied successfully
:: https://social.msdn.microsoft.com/Forums/en-US/d599833c-dcea-46f5-85e9-b1f028a0fefe/robocopy-exits-with-error-code-1?forum=tfsbuild
robocopy {package_dir}\\config %OUTPUTS_DIR%\\config /E /NFL /NDL /NJH /NJS /nc /ns /np
robocopy {package_dir}\\lib %OUTPUTS_DIR%\\lib /E /NFL /NDL /NJH /NJS /nc /ns /np
robocopy {package_dir}\\test %OUTPUTS_DIR%\\test /E /NFL /NDL /NJH /NJS /nc /ns /np
copy {package_dir}\\mix.exs %OUTPUTS_DIR%\\mix.exs || goto :error

cd %OUTPUTS_DIR% || goto :error

set DEPS_DIR=%TEST_SRCDIR%/%TEST_WORKSPACE%/{erl_libs_path}
set DEPS_DIR=%DEPS_DIR:/=\\%
set ERL_COMPILER_OPTIONS=deterministic
set MIX_ENV=test mix dialyzer
echo y | "{elixir_home}\\bin\\mix" local.hex --force || goto :error
echo y | "{elixir_home}\\bin\\mix" local.rebar --force || goto :error
echo y | "{elixir_home}\\bin\\mix" make_all || goto :error

REM need to start the background broker here
set TEST_TEMPDIR=%OUTPUTS_DIR%

set ERL_LIBS=%DEPS_DIR%

"{elixir_home}\\bin\\mix" test --trace --max-failures 1 || goto :error
goto :EOF
:error
exit /b 1
""".format(
            erlang_home = windows_path(erlang_home),
            elixir_home = windows_path(elixir_home),
            package_dir = windows_path(ctx.label.package),
            erl_libs_path = erl_libs_path,
            rabbitmq_run_cmd = ctx.attr.rabbitmq_run[DefaultInfo].files_to_run.executable.short_path,
            test_env = "",
            filter_tests_args = "",
            dir = "",
            package = "",
        )

    ctx.actions.write(
        output = output,
        content = script,
    )

    runfiles = ctx.runfiles(
        files = ctx.files.srcs + ctx.files.data,
        transitive_files = depset(erl_libs_files),
    )
    runfiles = runfiles.merge_all(
        [
            erlang_runfiles,
            elixir_runfiles,
            ctx.attr.rabbitmq_run[DefaultInfo].default_runfiles,
        ] + [
            ctx.runfiles(dep[ErlangAppInfo].include + dep[ErlangAppInfo].beam)
            for dep in ctx.attr.deps
        ],
    )

    return [DefaultInfo(
        runfiles = runfiles,
        executable = output,
    )]

rabbitmqctl_private_test = rule(
    implementation = _impl,
    attrs = {
        "is_windows": attr.bool(mandatory = True),
        "srcs": attr.label_list(allow_files = [".ex", ".exs"]),
        "data": attr.label_list(allow_files = True),
        "deps": attr.label_list(providers = [ErlangAppInfo]),
        "rabbitmq_run": attr.label(
            executable = True,
            cfg = "target",
        ),
    },
    toolchains = [
        "//bazel/elixir:toolchain_type",
    ],
    test = True,
)

def rabbitmqctl_test(**kwargs):
    rabbitmqctl_private_test(
        is_windows = select({
            "@bazel_tools//src/conditions:host_windows": True,
            "//conditions:default": False,
        }),
        **kwargs
    )
