load(
    ":elixir_build.bzl",
    "elixir_build",
)

def elixir_home():
    elixir_build(
        name = "elixir",
        sources = native.glob(
            ["**/*"],
            exclude = ["BUILD.bazel", "WORKSPACE.bazel"],
        ),
    )
