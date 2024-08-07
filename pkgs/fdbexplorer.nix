{ lib
, buildGoModule
, fdbPackages
, fetchFromGitHub
,
}:

buildGoModule rec {
  pname = "fdbexplorer";
  version = "0.0.21";

  src = fetchFromGitHub {
    owner = "pwood";
    repo = "fdbexplorer";
    rev = "v${version}";
    sha256 = "sha256-OXv0VDDdpIbuphSc+z1ImT1xTPIVlHmThKmvoHCSLjw=";
  };
  vendorHash = "sha256-5tlHi+PtolGhCKPsZgOed1rTLsWi7UyFaq7JZWBxtzo=";

  buildInputs = [
    fdbPackages.latest.dev
  ];

  meta = with lib; {
    description = "Utility for exploring FoundationDB";
    homepage = "https://github.com/pwood/fdbexplorer";
    license = licenses.mit;
    maintainers = with maintainers; [ alekseysidorov ];
  };
}
