# offline checks for lib/chaki/rsa.bend. The keys, the message and every signature were
# made with openssl 3.6.4:
#
#   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out k2048.pem
#   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out k4096.pem
#   openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:1024 -out k1024.pem
#   printf 'chaki rsa check\n' > msg.bin ; : > empty.bin ; printf 'a' > one.bin
#   openssl dgst -sha256 -sign k2048.pem -out v256.bin msg.bin
#   openssl dgst -sha256 -sign k2048.pem -sigopt rsa_padding_mode:pss \
#     -sigopt rsa_pss_saltlen:digest -out p256.bin msg.bin
#
# ... and the same with -sha384, -sha512, empty.bin (ve), one.bin (v1) and the 4096-bit
# key (bv256, bp256, bv384, bp384, bv512, bp512) and 1024-bit key (kv256). The 4096-bit
# vectors below come from a second k4096.pem made the same way: only one 4096-bit key
# appears here, with all six of its signatures. Each one answers "Verified OK" under
# `openssl dgst -verify`. n below is the Modulus= line of
# `openssl rsa -in <key> -noout -modulus`, e is 65537, and each signature is the
# xxd -p of its file. These keys exist only for this check: the private halves are not
# kept, nothing here came from a real peer, and the public keys are public.
import Base
import ../lib/chaki/bytes.bend as Bytes
import ../lib/chaki/check.bend as T
import ../lib/chaki/rsa.bend as Rsa
import ../lib/chaki/sha2.bend as Sha2

# the bytes of a hex string
def x(s: String) -> List<&2, U32>:
  Bytes.of_hex(s)

# the message all the 2048-bit signatures but ve.bin and v1.bin cover
def msg() -> List<&2, U32>:
  Bytes.of_ascii("chaki rsa check\n")

# the public exponent of the three keys
def e() -> List<&2, U32>:
  x("010001")

def n2048() -> List<&2, U32>:
  x("ABBF9B281BCE15A774CEEC1D1251D44BEE242F3D6A3F23F6F3996F5122C6B3086E0E274C56EA567A8A0AB07CD210CC8E73437930845E4FA6FA240D963A136F009C0C0717B23AD7AB23EC8401DAB34F90BA18AEC8BCF787D7E4D950ED2F8AFDEA558255F6EB60BC385839CC0E8D02577D88DC274BF2219332E492D0DBB0E02248E85A81EB4BD497066ADEF39568957CA78D661359879C17959B8D50863ABB517C891EBEF102DCE1313B2EA87CCFD6D9B8CB848830ED84F8161D4EDFE9251228DFF0EF6380022D1F3B565FBFE5766970EA13BAE84B484E7D887B97002A5A205E4ACA2628AD7893A8BC32CB5C090E8924FDFEB371E366E38E7163643C524FA89C43")

def n4096() -> List<&2, U32>:
  x("A7D17DC9C33E41CA27841DBC26B089A38C0A3AE2B307BEAD7974A8C43C08DCC0A0F78B6676C2E50EFD80A2F11AE5D9B31F4E61421BA274D42EA5447BB03C2ED3B1CBF608531F216D0A488CC57DB0C51D5F9C48F190D73262E8D2D4906AE5BA0A663656925FD4A456F08783051008647EC2DA2CF84E033AD5E073FD648B9EE4861C6CE977607084CED46E770670F996C0A7468E6F9196FF650DD41A4AA7366DA5AE77C24C8BEB245FEE44094ED51153CCB09A85FD8E80F8946B65BFD2B82EB7C798DA5D7485BF1E4DC4143C9E6EFB95A30F285C4EB725A85DF5FF25BF9F6D7D0C360BBCA2F5F307F017E910E17D8042DA88D6C434399831F717468D73A05E79B7957528D99AAFD2CFE29DFFF51D6AA3DEF01B2673F75163C3A9E48366F035FD7EB01AAE092F3C0FEC6C27435DE3DCA65534051A9DE6775E0541C139CCF65B30B4E8EE4800C2E8D1FD80BA58625B02482198B7B78E23C15473B5D5D254673A014B59F4F8C7BBB191720E885573652D8A440B4689C3E1410F148BF25DC47D0D92742A0F55729765BB5EFC08C84B700887629CD4648CC9FF028EC0A3E2CC7E6FBE0CC4A956A9ED9E0B75C251829550B98DF58AE921805AD06CFEC154A42A2FF179F37AF5586121A8A7D5B1DC13C4B3C373778055EC8110ECE979E84AAF1751B9DB9A9AC1B0FFEAD3B6AD7ADB3615CA65A3D0275A957FED2A5C1B6A9E5336C61EE91F")

# a 1024-bit modulus, below the floor pkcs1 and pss keep
def n1024() -> List<&2, U32>:
  x("B4532CCC0123D5806C7B1D64A29243ECBFDE4193309AD4F8095E3D9EB596F6C6A5A5737712D45BD95C08FC7941444189614FA2FC25B9B5AD06E1DAB5C1A7D0B092A4A901A53EEB7F0F9D952521B3F5DD2B6071A86401BDED812B0740AE25A90C80C1B2B87E239696F815A27959620F07DA7D3216CEBE76B127AD757505A1C481")

def v256() -> List<&2, U32>:
  x("03aeeaba4360a144bddd33a531afa64085bcefc220dc1c49b8934882db7a576072703c7282bdb9613b0d28dc9195646a0f589566fd319d3471e43b2957a8b1e48d46ec7af28765856c7240004d251411830c8f7afeb8455bbcb9d0c9d11ea0a3a401d8be99bcceea39a9e01c39365bce83ebc80b3265476bd9cf1a4033e1b7ad863d80531b34fb1eec10730de1cab16bed11072463c2244dc98d8fcef1d25eff181e7f0144f9dc88b25b11219e1ddc7377c2e87adde1f57fb612e7bf60f27e831ff4a19d68be1a2f0fcd1845262b4a4a56a6071f68772fd41160a1f07f48d832162f5482f154714ccf7da1fa3f45d43acea62a6bad55daa17a1d1fe1fb0461fa")

def v384() -> List<&2, U32>:
  x("1fe10c4c671eb0a918a71012465e28d5144cf5db858fc868cd4a7396199956da7a797ce6182565a9a531a58bc0f1f7c8c3c2d711e75d76ade6d10ee8cc9168913be3899c3a9f06f1d7c8b9f2d532a4ffa0f5815da05e71ca01fca993ff4936d4525675284754bf3acc944d298a73da28a50c8dacc3c443a6e94f4fc688288313fe04be03d6f9fc5eab5c4d710cb8013d2a957f17cd0774798301f4fc6adcd0b979ca7fddad1823767de71bdab5ea30888b6c9cbaa075ff2c57f5a80b0e66506073083fb777649171f6ca65df46c1e951b09c872da943de7e864afcaec033065d009d9aafd9d322844f8a8f4e11871b3c7a40afbec0d145c1ef217d71a48055c2")

def v512() -> List<&2, U32>:
  x("47de5e8d48ffd773130c67ece8a9a2ca5d4615dde13cd466c1382ad27df30ba565fea531ceee6e17a49b701f7d1cda13f9988a2eadaa5b1f4686ba799284733d35ff379757584660601f5b8adad4a0eba544079005fe3e3065f2aa42f22d4bddd2374dbb9c834d33c7dfcb61fb46e1847343915a6f4ab5342cd874c73ca84c0d4cca12acc5e8716f3b9bf7d1ed94f2973c77bd0fc008499c92986c1206b971fe7dfe7c1c38323bca9f466c9289250e9321cb41811e4520bc87f3a4ab7a01142e0878365391a71d27fe0eb2c4b6a9ef2042ad4be790e829d264b18243f4ac163d1671acba1a3a7a69e5c1aad4a859e1fc033f39eb669e0132ab2eaef7e5992854")

def p256() -> List<&2, U32>:
  x("54c75b4c4a5ffa47c298d4bd54fa24abbe434b9ae4eb889458ac4b78e26c2147da2babc6eaee5f410476ae1feb79483d2af68f0f83558da0f4afe99d40bfc585ba355e262e45d3a6e01d4bd7a464af0b5923aa33f658c959cd04ea2ce20a2c668a39bc3eccf7da9526e0d16e1836117708fa38ff0b5e2c6b4ca867c9fc1f8e7fa5490b2221b795f7f1c1660c2df521a8b26cf8d5a485707ecb605fe7096642e4df893b33902a54999665f894c64c7a16853f0f45aaf030e6e21a144d3b15a981536c84986f275f6dcb299c9aac8f2f9c5f022e3ea6926f2d35515442227ed3bf7ef221bbef1e6701013c4a9fb2948915daccd2662d20395842d8899d6f81ccbd")

def p384() -> List<&2, U32>:
  x("22b3808037c663acae5c8b1aa07c17a3d10808a3a3e23e9b3134753d9c0d8a8f6f12cb548e9e21ee692df3cda4c45bd6b25938495cb5c1dbc72fc8515ed3f9c672f7aff6f9371342fc883b27c9520677b13d8388d54308e2f5965ce4f9e97387906eb00091bdedc224c1cf573f74bfd8715b585549bf7b204d1503347bd5538faf1e28bffafca51e3ac1a192ad23075ea4ba33782619b22c0906c5e2f86e7e10706a0550ac5c31f3aa96607a6abbd256247f538947ed31fa26546b83c25d088a55be4c4b3269c57eeb2643fbf4b4168840e0b15ad87c264738aeb25039e6d8ae763fcb764560ea3c7db1a2d66abc3518281bf8d9be6894512533f2e3d91284e5")

def p512() -> List<&2, U32>:
  x("82bafe8eb496fcf80102e78c920e076d862a2eec8273afff4d714f3f0e2a9c261f6dd5c54e54725cabf8109eedc3a844480f68b5e815d7e820fb9abc474b027016419f6ac634c0af7d5da7cf6a4878d5f26b55c1586227ebe902f0c5b076a2f97e8295547840e7f878b63246de1a508a38aa4d0bb634d0a1ff4f3988f2b3660448c3d7421bd366533ab10025435f7aeeabfa970b377a36f81b1c431db55228d726c8a5c2424e7dd557013fe8a062e66907c8e7ef6b0038bc4bfe6b3b81e2a1daafa03fbcaf7ed638595ec2362845e1f7fe45bb82e2daaaf1115ec6dd589b1875fa24739b098b7e792c9e542e52a4e1c06ed3c8597d39b30e9b38acd62071d095")

# the empty message and the one-byte message "a", both signed with SHA-256 PKCS#1 v1.5
def ve() -> List<&2, U32>:
  x("30b20d9dd5ccaf56ca0284a57b4cb4563b96e4eb397ccfca7bd9cf75e5d96fab03ad0ca83ebc13be06a9dc38bb21e3dc977b027bd4cb998282e1e302344cf679b09aaa2bd0635362c21e002651b4d377df96f0861aa812963030706a4894dd76a9c5e71f7a4945aa613ef047c4949520d312cc7a7948934d40fd9aee73f97bd9ffe3528c11861382dcda144215eca8846ef62ceb63748916c1556ddbeaa96b98233cbab99ca31732889f184e5ae64fb6fc35e4f0974fb752ee33e137855b1a27543253cd73276b453a168837bacd2472912b1ebe64744f7755ad198ed88e6d45ab77bf5197b116c7180be04b107ce294b2f97a6f44e9d04e735cd1651567ede1")

def v1() -> List<&2, U32>:
  x("34738915f8fcce758e635367e80fc2672628815aa6d2cd011b7ee3c3776fc2dd9c809f6f7e132da07796d6ed8bb71465ce1a112a03b5163b0faa7d3782fa8abd9825ce963235e02a0c717ac55860b68b139cea1eeb937ab1ca57df45a02b466bf71d50ee6dbd617d2782b2565bfa6c92243a76c5a9309f03c51808125c4993902b5592931949e32aae8fead8124ca2f07c6d6bec176530975f0f47f31372dcc16a1410aed5a3a8e8a0819f33187de518a98feea0208273f83589925064de439519cbdfad50ccdca4818d2c764f632620073796b38bcfca74f385242baf6b483ac6b8729e18cda58b18bde3676c8d45e7149bd04c4815a1f78daa37f01a2447ce")

def bv256() -> List<&2, U32>:
  x("012f231f18f6cfeb46ddd0708dc1117ed422737b711194a6e940115b6375a4cd232c19403ee0c81aad099f05601e977d9d5c86d5245ce6fb4724ff1c1b681654535308a1b096e5e14d9280c69dfc3a1db143876abbbaa2e3e7166830822e421e5efacce83a7a6f207d1918e412ecd5be996da370047595b030a62e12caa582985a59432e6d38e2fff51b039f5050b702c2f64f6968a51968c53407a47e243ef885a8c13be62fbb019e5f4cf2e2ed48e62c7e1a28b7d50168ef23a191221f2dcd29e784b9976b12e8479624ccf699de3ee1bb4ff78abac535a5e12b5bdbc8d58f781a4b4d270eea6d28c0b794b181590265d80a42d0cd77bad0e6fd4025b94a5d337d83fa8c4bbd19f4f89c0402e9f26ca32e29586e47a46d7236b422669c24949106f7ea6b486b7cf85110b3aeeab4c9060fdf99880d4e562c3807f06ccf0b11cbc896114204d4b0c3aea43b786cddcf95f0d8a84226f19c837ade448d06441421b3dd44e8d2c0000997bb1f5ad830d101a10d3b501d27df63951c163b957c9f5f33a143c06c9e26cce0f0e5bfcfb4fdd34e9e3e1015c7c2fd9a6bd8b773025349a787a975c097fc871e83397d9b44c0ede03404a431f5b7079e3c92a602ff7fbe346591dca395309089a181927fbfea9e1798c03ee64cedbbc989072643bce2b7fb50edebe44bec79526cc98b4d1d1a807ad512c2b4199de064fe4c34463d46")

def bv384() -> List<&2, U32>:
  x("3933dd00d809f0571d3c98304aaec4f1d3a1bb3a75fdc4e1904112f9edf238f7837761aaff507f48c0996b19f99d0a577e8a90d410a62d031d8e15b7c22c6bd8832201a26a4e10dc941c54af47d610a9414879cf0cb5eb60f4633dcbcb0f648f80a403d1ab6f5b305ae9854d5caec6a23b38ed76ef29354d6451767decdd3d3096e478210974702f326e8783db452323bbe03423f55fa8b5588181ec1d4d73f15cbec4224e1eead7b7c61b3f7567f8ee3b85c72a940c5f3594d5da8a131598f67b40df41353d15c8339e9ed5ac625250df769bae504a250a4d43e5e7e4ed34056e4e8558beb6a4a162d1a5c63af387018c19f21c804c7dd7bf5ba0369cf3615585c89c10f8cf1e21c451f919abd5c2d4363dbe60a136e6ad930c818af903a2277381a2560240352e76554d87ebb1f838e1694332f9b772e58716a7a2e87c363d443d4ef78136927b50b3629447e00041734dba8932513f92676c65580fc7e4db1e54fc41bb69338e73292b24be9c2b555cbb8635623b1912baf1c8a748d31364f00316a8bb67abf43a693ac13d9cc07dfb94497c88fe860f119ebc39b05f2c1b0d6ebd1f78c34eae43778b4345753f8cbef3988164d69501805a4744fe70f79138e4d6fc53298f6aaa2834970b5031053a56105e05fc0b3743996c107ae9affd8135da6f53f8c14d45221b2d69da77893ea461e950d3c33ff67f782af8c75af3")

def bv512() -> List<&2, U32>:
  x("50cf75b8cc86db9b9dd4d6f7a70e59a425e76b0db53c8885cfda975e709359cbade642ff51cb896dce3b1b1561e3eb6393c96fee8f559bce3b2cf1e4b444fe6bb729b7eee9a3e148c93e2b092d0f0b09864cbace8c19fea03abcf768bb22c39ed3be6f13ac5bbb62de3ff0653b1cdd3957eeaafc4ba2130225f5d2e13f28a41aad7781001baa44cdcc15596bcbfb0ca45cabb47b9ae330ea44b000ae26fd289100db9021c780841cc9332676ecc8ea3576a86bd68e010a36bcf9efe8f188b3286f12fe7845e795e99cb6e3a7c22825e729a4dded7bf23dfdb08a79ba0225c1446f5ada1ec4929733e7c917aeb84862bdac1d129e93b9a56cce8e2137eaccb1d37f340ac2ed92e948afc85199d748f65875cbbd743263fc546301979e2eea16ed7f1677a499eb0f0da0252121650d090a3a1f0854470f76eab04de50c695fe85a66eef9cf8dad962bcd1aeade49fbf2d24bd014a02f1e14dd9504af5a216286c56769b09f76b606eb127f228fbb18fa5a029e62bf0c5b71773937ac5a871c855c6c89b78092dcdf13799af2646b544f56c63a23afde9e8f1a4877b58c8e8f0e3e1877c4dc502c49bf0870a3f0bf935f0007c930715c4c47aeab1d4dd23be3424d5b9458a6e0f65e390848488503c9a8aa6dbe3216e1f7b7b18e662cc5fffa8b3a24892b9aee33d8f46270d100133df231a19c8ddc379058dfbb521d1ec1ec68bc")

def bp256() -> List<&2, U32>:
  x("40e43865e7bb34446bf8ea390a0139a410d82767c9d99cdbb78a30007d885bac2952ae17059267294eeb110b1329358fba888e5f78bf3a4317ae4b1226430637c4d2e223d8125b34543c84ec42703fcc330ccdb24144ccf8bd0df20349cff65845113710b179d5cc874eeef38a966cae24ec2c9b93dc86195d4e76a57d58e13ab460ac4434d19dad1e3f63f5bf5e33f8e2407819d1db02e51604137712b83ef2ffce61440b292803fcabb8f78a44e85bae90c9d7acc1371cb7481ce50a3ba7925628abe68edad111930f36b7c9c43f2a987ec2ce0274b35b1c31aa120d6ba51237b545a7a73c4a8348c42e30bc97c21912b4615539a1115cdf54ca030d5dc9d7c2de1155fedd7e9ff015932188462c5497487d5892a6def25557efbb9f7126db678147628a4a8e938e571bdd0949e7b66c41d37cd6d4e6df637706f2ee52541d9f505258207cefa771ba28ab6f860e79ea5012833b68a68036c31412b93580c31478f039355337c39d41241c2086de78e56b51fc3a1b707b8a0cc8d8ed0e45c24a12e614925dd507ea3aa10ce724861ac6411124e124691f513dd8a7b42aba276948a640e7fb8ea7920cc6b27755ae0185ec4af731c2555c265c86d2d9a38169d044855f1fb5ed4ee913691c43754b5762e9a7e707d871b02b845cd736bf330a92bae418566815ce9c8e0104687aba853d8fe5735f33d97c59102f63599da40c")

def bp384() -> List<&2, U32>:
  x("3bcc567459d98788e6ea3f98f1353fa36e24626619d3bafbbe358fb9c03e4f043f9d5a50748a549243f7828ac8ab25266d2d330dfea4c83ed3c0b2b6bf4e8f13f180bea5dd22cf673be014e16313143de3d32bd6879b8c84bd4b5e7c6a04bbbbc4630211a33ffa643306e1360d9c655cc666bf1a82714264dc42be768fa0fffcfb1a9f68ce4cc7c05f9dbafbe58f9377be553271ca1e93518b22ced64c5231e9798c3d5a85ea714bc106a4c983f6c7cd6c1346d8137bd35acd7d2efcea14879bf8b35b3d2ecfc8d47721fd015fe1d9b56823446b74435e5eb280e019a2db70bc69ecbac759a74b7c95c9a07b15a71fe8bdca6b540dd5d0290b5b6b7d3ffc1a6c305f83d08d7dfb2d4de597d0223d0e38e27d0cf908465f975390bdc105aa4f9ed6d6791dc00f0da49c70706ca9f2d6d8551fb984740b359bba2d53bb53a0e41f0ef590ad33c5f850f7ca6c835b0cac31f9e0ad28880e9f306dd4ab9094c11912a9fb9255c51ef4c9a1304557b3d8ec6784cac888b11c181dba9d7cd8e85aec44f4ba510422c855e9de7282009558e983105e877c9b1d3a022641ca01410bc7d60a1d7a109425908f397ba1e68f0297971c9b0e9a69ded83bff9f2d72e4042276cb302928b9c49446898f3e11d473c83a3ecfca7485a7ee48ad558754c07b08b3312699c97e5a3ae12c9fafe2c77758ee2b60a1c49570123bc7263678b407c5cf")

def bp512() -> List<&2, U32>:
  x("7240cd7af72782226df4f18c3708e443ec2bf80763a8ef73e38acd976f2180d513bf38bb048a0300b30c285b4637263557fd07166758b96b336b8b19f50edcbe291485ae438ee34fa2c73d49fff87896a66b3b22fc534801fd66ec2b3a560eee57babbc9a919983641793a1d064d86647b5b6ec430444e416516e6af4a25c495d2232cf69aedc5193fae726cf2dfa1c9d74ab1ffdef5bafadd7818850bae8fe485234245af3c0a7e9cdb7b775bde46bb7bca41afcbd73023333247efb35a098e28fddf2a5ad189b36c6e2ef49aad72805127f2c7c6e368a76245fbacc0f4f46476428086a6540794dc116ca44f801c2db73fd157c086e5e7fe052fb41e7fef0f5f82ed7f7ff72b4fb85208c8469ceca788edf57e74b8777c9881ed96ce3e1b571823f583f8c6e628be5b4773797b7229077a9b217de727c861c3efe973d6bfaf6c84bbcf1854e9086c54c7a2723baee7c7408d02d385a1f6d866b5b379590b6d96898f5b59b29b3c8cde18564241b6ff658a002cb28e2107a613b1109cb706c3cdcc2e3d507adb8b07dfb867d98024f40e021975aa5d1d67644258b46477fd5865c7c411ef7101a8a45af636e5cfa31cd3de011f0d3f0dab44dd76e2e3e7beecafea8954264b49b5cfb0852a31757714868591220810b266526146a9a3a103d393cef95c0fda18c6a50f6465e97e503d8fa03a5ce33c33c6f41bb41527fd1626")

def kv256() -> List<&2, U32>:
  x("4107e77c013227a2e63d7865ecec8ca79ec46e9ef73f51ca7e20853c78a4276d220b961636f44dff38684838690fbf0fbf639ee54e112354554213e67ad7d33b90df878bb513039c227a4113eea1d85dc080a27f7cb725731c218192e1884faba6e60f0a621a92eee4f17255565374b8e196520db7dfcf26271158b36e0faf81")

# the same bytes with the low bit of byte i flipped
def flip.go(xs: List<&2, U32>, +i: U32, +k: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}:
      Bytes.rev(acc)
    case Con{+h, t}:
      flip.go(t, i, (k + 1 : U32),
        Bool.pick(U32, U32.is_eq(k, i), U32.xor(h, 1), h) <> acc)

def flip(xs: List<&2, U32>, i: U32) -> List<&2, U32>:
  flip.go(xs, i, 0, Nil{})

# the signature with its last byte dropped
def short(+xs: List<&2, U32>) -> List<&2, U32>:
  Bytes.take(xs, Nat.sub(U32.to_nat(Bytes.len(xs)), 1n))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(T.ok("RSA 2048 pkcs1 sha256", Rsa.pkcs1(Sha2.S256{}, n2048(), e(), msg(), v256())))
    IO.print(T.ok("RSA 2048 pkcs1 sha384", Rsa.pkcs1(Sha2.S384{}, n2048(), e(), msg(), v384())))
    IO.print(T.ok("RSA 2048 pkcs1 sha512", Rsa.pkcs1(Sha2.S512{}, n2048(), e(), msg(), v512())))
    IO.print(T.ok("RSA 2048 pss sha256", Rsa.pss(Sha2.S256{}, n2048(), e(), msg(), p256())))
    IO.print(T.ok("RSA 2048 pss sha384", Rsa.pss(Sha2.S384{}, n2048(), e(), msg(), p384())))
    IO.print(T.ok("RSA 2048 pss sha512", Rsa.pss(Sha2.S512{}, n2048(), e(), msg(), p512())))
    IO.print(T.ok("RSA 2048 pkcs1 sha256 empty message", Rsa.pkcs1(Sha2.S256{}, n2048(), e(), Nil{}, ve())))
    IO.print(T.ok("RSA 2048 pkcs1 sha256 one-byte message", Rsa.pkcs1(Sha2.S256{}, n2048(), e(), x("61"), v1())))
    IO.print(T.ok("RSA 4096 pkcs1 sha256", Rsa.pkcs1(Sha2.S256{}, n4096(), e(), msg(), bv256())))
    IO.print(T.ok("RSA 4096 pkcs1 sha384", Rsa.pkcs1(Sha2.S384{}, n4096(), e(), msg(), bv384())))
    IO.print(T.ok("RSA 4096 pkcs1 sha512", Rsa.pkcs1(Sha2.S512{}, n4096(), e(), msg(), bv512())))

    t0 : Nat <- IO.now()
    big : Bool = Rsa.pss(Sha2.S256{}, n4096(), e(), msg(), bp256())
    t1 : Nat <- IO.now()
    IO.print(T.ok("RSA 4096 pss sha256", big))
    IO.print(T.ok("RSA 4096 pss sha384", Rsa.pss(Sha2.S384{}, n4096(), e(), msg(), bp384())))
    IO.print(T.ok("RSA 4096 pss sha512", Rsa.pss(Sha2.S512{}, n4096(), e(), msg(), bp512())))
    IO.print("     4096-bit pss verify took " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")

    # a bit flipped in the signature, one in the message, the wrong hash, the other scheme
    IO.print(T.ok("RSA 2048 pkcs1 sha256, signature bit flipped",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), e(), msg(), flip(v256(), 0)))))
    IO.print(T.ok("RSA 2048 pkcs1 sha256, signature last bit flipped",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), e(), msg(), flip(v256(), 255)))))
    IO.print(T.ok("RSA 2048 pss sha256, signature bit flipped",
      Bool.not(Rsa.pss(Sha2.S256{}, n2048(), e(), msg(), flip(p256(), 0)))))
    IO.print(T.ok("RSA 2048 pkcs1 sha256, message bit flipped",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), e(), flip(msg(), 0), v256()))))
    IO.print(T.ok("RSA 2048 pss sha256, message bit flipped",
      Bool.not(Rsa.pss(Sha2.S256{}, n2048(), e(), flip(msg(), 0), p256()))))
    IO.print(T.ok("RSA 2048 pkcs1 sha256 signature, wrong hash",
      Bool.not(Rsa.pkcs1(Sha2.S512{}, n2048(), e(), msg(), v256()))))
    IO.print(T.ok("RSA 2048 pss sha256 signature, wrong hash",
      Bool.not(Rsa.pss(Sha2.S512{}, n2048(), e(), msg(), p256()))))
    IO.print(T.ok("RSA 2048 pkcs1 signature as pss",
      Bool.not(Rsa.pss(Sha2.S256{}, n2048(), e(), msg(), v256()))))
    IO.print(T.ok("RSA 2048 pss signature as pkcs1",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), e(), msg(), p256()))))
    IO.print(T.ok("RSA 2048 pkcs1 signature one byte short",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), e(), msg(), short(v256())))))
    IO.print(T.ok("RSA 2048 pss signature one byte short",
      Bool.not(Rsa.pss(Sha2.S256{}, n2048(), e(), msg(), short(p256())))))
    IO.print(T.ok("pkcs1 rejects a 1024-bit key",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n1024(), e(), msg(), kv256()))))
    IO.print(T.ok("pss rejects a 1024-bit key",
      Bool.not(Rsa.pss(Sha2.S256{}, n1024(), e(), msg(), kv256()))))

    # the malformed ends: an all-zero signature, one equal to n, and the exponents
    IO.print(T.ok("RSA 2048 pkcs1 zero signature",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), e(), msg(), Bytes.zeros(256n)))))
    IO.print(T.ok("RSA 2048 pkcs1 signature equal to n",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), e(), msg(), n2048()))))
    IO.print(T.ok("RSA 2048 pss signature equal to n",
      Bool.not(Rsa.pss(Sha2.S256{}, n2048(), e(), msg(), n2048()))))
    IO.print(T.ok("RSA 2048 pkcs1 exponent 1",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), x("01"), msg(), v256()))))
    IO.print(T.ok("RSA 2048 pss exponent 2",
      Bool.not(Rsa.pss(Sha2.S256{}, n2048(), x("02"), msg(), p256()))))
    IO.print(T.ok("RSA 2048 pkcs1 exponent 3",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n2048(), x("03"), msg(), v256()))))
    IO.print(T.ok("pkcs1 rejects a 256-byte signature on a 1024-bit modulus",
      Bool.not(Rsa.pkcs1(Sha2.S256{}, n1024(), e(), msg(), v256()))))
