# treefmt.nix
{ ... }:
{
  # Used to find the project root
  projectRootFile = "flake.nix";

  programs = {
    nixfmt.enable = true;
    beautysh.enable = true;
    deno.enable = true;
    taplo.enable = true;
  };
}
