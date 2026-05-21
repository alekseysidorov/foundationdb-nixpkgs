{
  lib,
  buildGoModule,
  foundationdb,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "fdbexplorer";
  version = "0.0.29";

  src = fetchFromGitHub {
    owner = "pwood";
    repo = "fdbexplorer";
    rev = "v${version}";
    sha256 = "sha256-Hxx3/qSLSn7i/iSzLLmgptWrzSNqpRkuf3ziVhmaCHU=";
  };
  vendorHash = "sha256-JCh2DQ0cAyQOQM6oBdBsE4VvOrZPKXF05GF+t8o55VM=";

  buildInputs = [
    foundationdb.dev
  ];

  meta = with lib; {
    description = "Utility for exploring FoundationDB";
    homepage = "https://github.com/pwood/fdbexplorer";
    license = licenses.mit;
    maintainers = with maintainers; [ alekseysidorov ];
  };
}
