# Combustion

```yaml
Usage: combust [-h] [--completion {bash,zsh,fish}] [-o <output_dir>]
       [--lua <lua>] [--luac <luac>] [--c-compiler <c_compiler>]
       [--linker <linker>] [-e <entry>] [-n <name>] [--graphical] [-v]
       [{self-extract}] [-S <source_dirs> [<source_dirs>] ...]
       [-L <library_dirs> [<library_dirs>] ...]
       [-l <link> [<link>] ...]
       [-R <resource_dirs> [<resource_dirs>] ...]
       [--cflags <cflags> [<cflags>] ...]
       [--ldflags <ldflags> [<ldflags>] ...]

Pack your lua project, and all dependencies into a single self contained file.

Arguments:
   {self-extract}        The type of project to pack. (default: self-extract)

Options:
   -h, --help            Show this help message and exit.
   --completion {bash,zsh,fish}
                         Output a shell completion script for the specified shell.
             -o <output_dir>,
   --output-dir <output_dir>
                         The output directory to write to. (default: build)
              -S <source_dirs> [<source_dirs>] ...,
   --source-dirs <source_dirs> [<source_dirs>] ...
                         The source directory to pack. (default: .)
               -L <library_dirs> [<library_dirs>] ...,
   --library-dirs <library_dirs> [<library_dirs>] ...
                         Location of C libraries
       -l <link> [<link>] ...,
   --link <link> [<link>] ...
                         Libraries to statically link
                -R <resource_dirs> [<resource_dirs>] ...,
   --resource-dirs <resource_dirs> [<resource_dirs>] ...
                         Additional resources to pack.
   --lua <lua>           Path to the lua executable (default: /usr/local/bin/lua)
   --luac <luac>         Path to the lua compiler, must be compatable with the lua executable. (default: <lua>)
   --c-compiler <c_compiler>
                         C compiler to use. (default: /usr/local/opt/llvm/bin/clang)
   --cflags <cflags> [<cflags>] ...
                         Flags to pass to the C compiler.
   --linker <linker>     Linker to use. (default: <c-compiler>)
   --ldflags <ldflags> [<ldflags>] ...
                         Flags to pass to the linker.
        -e <entry>,      The entry point of the project. (default: main.lua)
   --entry <entry>
       -n <name>,        The name of the project. (default: <entry>)
   --name <name>
   --graphical           (Windows only) Create a application which does not spawn a console window
   -v, --verbose         Print verbose output.

https://github.com/Frityet/combustion

```
