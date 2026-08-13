# Upstream source lock

Only the source files required to build the two deployed daemons are vendored.
They retain their BSD-3-Clause notices and were copied without modification
from these audited local upstream checkouts:

| component | upstream | commit |
|---|---|---|
| qrtr | <https://github.com/linux-msm/qrtr> | `0428c6541d230cdd253bfa76cef83341e1c2d178` |
| rmtfs | <https://github.com/andersson/rmtfs> | `b30a3eb38f9af283f18dbd3c7755653efc52c094` |
| tqftpserv | <https://github.com/linux-msm/tqftpserv> | `b6bb92d40cfffe28621abcf7bfaa6d99beea46cb` |

The resulting executables are generated build artifacts and stay out of Git.
The reference device used hashes
`0E29B8B635C937277C2A11ADF8B79B7217A83B63EEACB536C44D0E02A2AF6D59`
for `rmtfs` and
`E3BF31E3526DF6EDB2E03DFAA1FF1D359BE08BFE56277973B7E83854435C9A41`
for `tqftpserv` during the recovery that established the package requirement.
