rec {
  # Source: https://github.com/NixOS/nixpkgs/blob/41de143fda10e33be0f47eab2bfe08a50f234267/pkgs/applications/editors/neovim/utils.nix#L24C9-L24C9
  # this is the code for wrapNeovim from nixpkgs
  wrapNeovim = pkgs: neovim-unwrapped: pkgs.lib.makeOverridable (legacyWrapper pkgs neovim-unwrapped);

  # and this is the code from neovimUtils that it calls
  legacyWrapper =
    pkgs: neovim:
    {
      extraMakeWrapperArgs ? "",
      # the function you would have passed to python.withPackages
      # , extraPythonPackages ? (_: [])
      # the function you would have passed to python.withPackages
      withPython3 ? true,
      extraPython3Packages ? (_: [ ]),
      # the function you would have passed to lua.withPackages
      extraLuaPackages ? (_: [ ]),
      withPerl ? false,
      withNodeJs ? false,
      withRuby ? true,
      vimAlias ? false,
      viAlias ? false,
      configure ? { },
      extraName ? "",
      # I passed some more stuff in
      nixCats,
      runB4Config,
      optLuaAdditions ? "",
      aliases,
      nixCats_passthru ? { },
      extraPython3wrapperArgs ? [ ],
    }:
    let
      # accepts 4 different plugin syntaxes, specified in :h nixCats.flake.outputs.categoryDefinitions.scheme
      parsepluginspec = opt: p: let
        optional = if p ? optional && builtins.isBool p.optional then p.optional else opt;

        attrsyn = p ? plugin && p ? config && builtins.isAttrs p.config;
        hmsyn = p ? plugin && p ? config && !builtins.isAttrs p.config && p ? type;
        nixossyn = p ? plugin && p ? config && !builtins.isAttrs p.config && !(p ? type);

        type = if !p ? config then null
          else if nixossyn then "viml"
          else if hmsyn then p.type
          else if attrsyn then
            if p.config ? lua then "lua"
            else if p.config ? vim then "viml"
            else null
          else null;

        config =
          if attrsyn then
            if type == "lua" then p.config.lua else p.config.vim
          else if hmsyn || nixossyn then p.config
          else null;
      in
      if p ? plugin then {
          inherit (p) plugin;
          inherit config type optional;
      } else {
        plugin = p;
        inherit optional;
      };

      # this is basically back to what was in nixpkgs except using my parsing function
      genPluginList = packageName: { start ? [ ], opt ? [ ], }:
        (map (parsepluginspec false) start) ++ (map (parsepluginspec true) opt);

      pluginsWithConfig = pkgs.lib.flatten (pkgs.lib.mapAttrsToList genPluginList (configure.packages or { }));

      # we process plugin spec style configurations here ourselves.
      plugins = map (v: { inherit (v) plugin optional; }) pluginsWithConfig;
      lcfgs = builtins.filter (v: v != null) (map (v: if v ? type && v.type == "lua" then v.config else null) pluginsWithConfig);
      vcfgs = builtins.filter (v: v != null) (map (v: if v ? type && v.type == "viml" then v.config else null) pluginsWithConfig);
      luaPluginConfigs = builtins.concatStringsSep "\n" lcfgs;
      vimlPluginConfigs = builtins.concatStringsSep "\n" vcfgs;

      # this is basically back to what was in nixpkgs
      res = pkgs.neovimUtils.makeNeovimConfig {
        inherit withPython3 extraPython3Packages;
        inherit withNodeJs withRuby viAlias vimAlias;
        inherit extraLuaPackages;
        inherit plugins;
        inherit extraName;
      };
    in
    (pkgs.callPackage ./wrapper.nix { }) neovim ( res // {
        wrapperArgs = pkgs.lib.escapeShellArgs res.wrapperArgs + " " + extraMakeWrapperArgs;
        # I handle this with customRC 
        # otherwise it will get loaded in at the wrong time after startup plugins.
        wrapRc = true;
        # Then I pass a bunch of stuff through
        customAliases = aliases;
        runConfigInit = configure.customRC;
        inherit (nixCats_passthru) nixCats_packageName;
        inherit withPerl extraPython3wrapperArgs nixCats nixCats_passthru
          runB4Config optLuaAdditions luaPluginConfigs vimlPluginConfigs;
      }
    );
}
