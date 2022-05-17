load(
    ":elixir_build.bzl",
    "elixir_build",
)

def elixir_home(index = None, erlang_installation = None):
    elixir_build(
        name = "elixir",
        erlang_installation = erlang_installation,
        sources = native.glob(
            ["**/*"],
            exclude = ["BUILD.bazel", "WORKSPACE.bazel"],
        ),
        index = index,
    )
