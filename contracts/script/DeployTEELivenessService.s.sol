pragma solidity ^0.8.12;

import "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {EmptyContract} from "./utils/EmptyContract.sol";

import "@dcap-v3-attestation/utils/SigVerifyLib.sol";
import "@dcap-v3-attestation/lib/PEMCertChainLib.sol";
import "@dcap-v3-attestation/AutomataDcapV3Attestation.sol";
import "./utils/DcapTestUtils.t.sol";
import {TEELivenessVerifier} from "../src/core/TEELivenessVerifier.sol";
import {AttestationVerifier} from "../src/core/AttestationVerifier.sol";
import "./utils/CRLParser.s.sol";

contract DeployTEELivenessVerifier is Script, DcapTestUtils, CRLParser {
    string internal constant defaultTcbInfoPath =
        "dcap-v3-attestation/contracts/assets/0923/tcbInfo.json";
    string internal constant defaultTcbInfoDirPath =
        "dcap-v3-attestation/contracts/assets/latest/tcb_info/";
    string internal constant defaultQeIdPath =
        "dcap-v3-attestation/contracts/assets/latest/identity.json";

    function setUp() public {}

    struct Output {
        address SigVerifyLib;
        address PEMCertChainLib;
        address AutomataDcapV3Attestation;
        address TEELivenessVerifier;
        address TEELivenessVerifierImpl;
        string object;
    }

    function getOutputFilePath() private view returns (string memory) {
        string memory env = vm.envString("ENV");
        return
            string.concat(
                vm.projectRoot(),
                "/script/output/tee_deploy_output_",
                env,
                ".json"
            );
    }

    function readJson() private returns (string memory) {
        bytes32 remark = keccak256(abi.encodePacked("remark"));
        string memory output = vm.readFile(getOutputFilePath());
        string[] memory keys = vm.parseJsonKeys(output, ".");
        for (uint i = 0; i < keys.length; i++) {
            if (keccak256(abi.encodePacked(keys[i])) == remark) {
                continue;
            }
            string memory keyPath = string(abi.encodePacked(".", keys[i]));
            vm.serializeAddress(
                output,
                keys[i],
                vm.parseJsonAddress(output, keyPath)
            );
        }
        return output;
    }

    function saveJson(string memory json) private {
        string memory finalJson = vm.serializeString(
            json,
            "remark",
            "TEELivenessVerifier"
        );
        vm.writeJson(finalJson, getOutputFilePath());
    }

    function deploySigVerifyLib() public {
        vm.startBroadcast();
        SigVerifyLib sigVerifyLib = new SigVerifyLib();
        vm.stopBroadcast();

        string memory output = readJson();
        vm.serializeAddress(output, "SigVerifyLib", address(sigVerifyLib));
        saveJson(output);
    }

    function deployPEMCertChainLib() public {
        vm.startBroadcast();
        PEMCertChainLib pemCertLib = new PEMCertChainLib();
        vm.stopBroadcast();
        string memory output = readJson();
        vm.serializeAddress(output, "PEMCertChainLib", address(pemCertLib));
        saveJson(output);
    }

    function updateAttestationConfig() public {
        string memory output = readJson();
        AutomataDcapV3Attestation attestation = AutomataDcapV3Attestation(
            vm.parseJsonAddress(output, ".AutomataDcapV3Attestation")
        );
        vm.startBroadcast();

        {
            VmSafe.DirEntry[] memory files = vm.readDir(defaultTcbInfoDirPath);
            for (uint i = 0; i < files.length; i++) {
                string memory tcbInfoJson = vm.readFile(files[i].path);
                (
                    bool tcbParsedSuccess,
                    TCBInfoStruct.TCBInfo memory parsedTcbInfo
                ) = parseTcbInfoJson(tcbInfoJson);
                require(tcbParsedSuccess, "failed to parse tcb");
                string memory fmspc = parsedTcbInfo.fmspc;
                attestation.configureTcbInfoJson(fmspc, parsedTcbInfo);
            }
        }

        {
            string memory enclaveIdJson = vm.readFile(defaultQeIdPath);

            (
                bool qeIdParsedSuccess,
                EnclaveIdStruct.EnclaveId memory parsedEnclaveId
            ) = parseEnclaveIdentityJson(enclaveIdJson);
            require(qeIdParsedSuccess, "failed to parse qeID");

            attestation.configureQeIdentityJson(parsedEnclaveId);
        }
        vm.stopBroadcast();
    }

    function deployAttestation() public {
        string memory output = readJson();
        vm.startBroadcast();
        AutomataDcapV3Attestation attestation = new AutomataDcapV3Attestation(
            vm.parseJsonAddress(output, ".SigVerifyLib"),
            vm.parseJsonAddress(output, ".PEMCertChainLib")
        );
        {
            // CRLs are provided directly in the CRLParser.s.sol script in it's DER encoded form
            bytes[] memory crl = decodeCrl(samplePckCrl);
            attestation.addRevokedCertSerialNum(0, crl);
        }
        vm.stopBroadcast();

        vm.serializeAddress(
            output,
            "AutomataDcapV3Attestation",
            address(attestation)
        );
        saveJson(output);

        updateAttestationConfig();
        verifyQuote();
    }

    function verifyQuote() public {
        string memory output = readJson();
        AttestationVerifier attestationVerifier = AttestationVerifier(
            vm.parseJsonAddress(output, ".AttestationVerifier")
        );
        bytes
            memory data = hex"03000200000000000a000f00939a7233f79c4ca9940a0db3957f0607c8f68886f8461a60efde00f096c085f2000000000e0e100fffff0100000000000000000000000000000000000000000000000000000000000000000000000000000000000500000000000000e7000000000000003e7830a35057b9938d0fd849d13e3d82dc4abba812f8ffebbbb3d0e5ff1dd661000000000000000000000000000000000000000000000000000000000000000060d7778210f93769ad6d1d26698df018f95d321fc64f750fdd286ed15882c58e000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000b5de8fdff76906d775d3747eac71bff66a9febe64a68e8f4d144a030c6f33662198c8bd17bc0ce6b5e38b9ae14dc4cd50542cb8ca10000060106f4a4e7b6069bcfb5ef5f38c0a95ca2903944b8d52445d9b685fb3304014e91064c1bd0fbb015e9500d7667a5755db19d0af171f20e7a02d29c240f86267f67b5ed7a420d0a5779985208c7acf8de59aeacade7f24cf0d247ae24f5d341a8cf47ab8751487a665c55830b59095d158a62df2c9401c7f5e19c78921ad29e20e0e100fffff0100000000000000000000000000000000000000000000000000000000000000000000000000000000001500000000000000e70000000000000096b347a64e5a045e27369c26e6dcda51fd7c850e9b3a3a79e718f43261dee1e400000000000000000000000000000000000000000000000000000000000000008c4f5775d796503e96137f77c68a829a0056ac8ded70140b081b094490c57bff00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000004abcdab784e9cf0f5eed7d11089612cb22276751e13562123db69577050a6cb70000000000000000000000000000000000000000000000000000000000000000e8a36091602d35d401fbc8944486f14659e51936938b93b4487ce15dcdf6518ab6fbc4e2d3a62b5043e888bdcfe7665add7186956a995ca7faa9a7abe18132a22000000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f0500620e00002d2d2d2d2d424547494e2043455254494649434154452d2d2d2d2d0a4d494945386a4343424a6967417749424167495554356c6a6756516436775163305532556f3668766b516e4b77554577436759494b6f5a497a6a3045417749770a634445694d434147413155454177775a535735305a577767553064594946424453794251624746305a6d397962534244515445614d42674741315545436777520a535735305a577767513239796347397959585270623234784644415342674e564241634d43314e68626e526849454e7359584a684d51737743515944565151490a44414a445154454c4d416b474131554542684d4356564d774868634e4d6a51774d7a497a4d5441784e6a45795768634e4d7a45774d7a497a4d5441784e6a45790a576a42774d534977494159445651514444426c4a626e526c624342545231676755454e4c49454e6c636e52705a6d6c6a5958526c4d526f77474159445651514b0a4442464a626e526c6243424462334a7762334a6864476c76626a45554d424947413155454277774c553246756447456751327868636d4578437a414a42674e560a4241674d416b4e424d517377435159445651514745774a56557a425a4d424d4742797147534d34394167454743437147534d34394177454841304941424e74360a4b7161764149587a3141686d64414a3339765847526b432f676d564350724261386b51436853385248377233676231787866314c5656664d634c5861477962590a6f76706b7642394a6472696a774f53665645536a67674d4f4d494944436a416642674e5648534d4547444157674253566231334e765276683655424a796454300a4d383442567776655644427242674e56485238455a4442694d47436758714263686c706f64485277637a6f764c32467761533530636e567a6447566b633256790a646d6c6a5a584d75615735305a577775593239744c334e6e6543396a5a584a3061575a7059324630615739754c33597a4c33426a61324e796244396a595431770a624746305a6d397962535a6c626d4e765a476c755a7a316b5a584977485159445652304f4242594546506b3877784b7a46797238736b49763246676e306e354c0a747751754d41344741315564447745422f775145417749477744414d42674e5648524d4241663845416a41414d4949434f77594a4b6f5a496876684e415130420a424949434c444343416967774867594b4b6f5a496876684e415130424151515156302b527a465552336b5879304131344b566c71316a434341575547436971470a534962345451454e41514977676746564d42414743797147534962345451454e415149424167454f4d42414743797147534962345451454e415149434167454f0a4d42414743797147534962345451454e41514944416745444d42414743797147534962345451454e41514945416745444d42454743797147534962345451454e0a41514946416749412f7a415242677371686b69472b4530424451454342674943415038774541594c4b6f5a496876684e4151304241676343415145774541594c0a4b6f5a496876684e4151304241676743415141774541594c4b6f5a496876684e4151304241676b43415141774541594c4b6f5a496876684e4151304241676f430a415141774541594c4b6f5a496876684e4151304241677343415141774541594c4b6f5a496876684e4151304241677743415141774541594c4b6f5a496876684e0a4151304241673043415141774541594c4b6f5a496876684e4151304241673443415141774541594c4b6f5a496876684e4151304241673843415141774541594c0a4b6f5a496876684e4151304241684143415141774541594c4b6f5a496876684e4151304241684543415130774877594c4b6f5a496876684e41513042416849450a4541344f4177502f2f7745414141414141414141414141774541594b4b6f5a496876684e4151304241775143414141774641594b4b6f5a496876684e415130420a4241514741474271414141414d41384743697147534962345451454e4151554b415145774867594b4b6f5a496876684e41513042426751515332344e7941564c0a305a514f6f4b6b3248645264346a424542676f71686b69472b453042445145484d4459774541594c4b6f5a496876684e4151304242774542416638774541594c0a4b6f5a496876684e4151304242774942415141774541594c4b6f5a496876684e4151304242774d4241514177436759494b6f5a497a6a304541774944534141770a52514968414f77516233563972364455427a73357256776541362b734a585451704435497661654a316b6338455844384169425935506b7677462b4b6a41464a0a7657622b76564c75454f6d53746c542f5a66686a46614239582b626a6c773d3d0a2d2d2d2d2d454e442043455254494649434154452d2d2d2d2d0a2d2d2d2d2d424547494e2043455254494649434154452d2d2d2d2d0a4d4949436c6a4343416a32674177494241674956414a567658633239472b487051456e4a3150517a7a674658433935554d416f4743437147534d343942414d430a4d476778476a415942674e5642414d4d45556c756447567349464e48574342536232393049454e424d526f77474159445651514b4442464a626e526c624342440a62334a7762334a6864476c76626a45554d424947413155454277774c553246756447456751327868636d4578437a414a42674e564241674d416b4e424d5173770a435159445651514745774a56557a4165467730784f4441314d6a45784d4455774d5442614677307a4d7a41314d6a45784d4455774d5442614d484178496a41670a42674e5642414d4d47556c756447567349464e4857434251513073675547786864475a76636d306751304578476a415942674e5642416f4d45556c75644756730a49454e76636e4276636d4630615739754d5251774567594456515148444174545957353059534244624746795954454c4d416b474131554543417743513045780a437a414a42674e5642415954416c56544d466b77457759484b6f5a497a6a3043415159494b6f5a497a6a304441516344516741454e53422f377432316c58534f0a3243757a7078773734654a423732457944476757357258437478327456544c7136684b6b367a2b5569525a436e71523770734f766771466553786c6d546c4a6c0a65546d693257597a33714f42757a43427544416642674e5648534d4547444157674251695a517a575770303069664f44744a5653763141624f536347724442530a42674e5648523845537a424a4d45656752614244686b466f64485277637a6f764c324e6c636e52705a6d6c6a5958526c63793530636e567a6447566b633256790a646d6c6a5a584d75615735305a577775593239744c306c756447567355306459556d397664454e424c6d526c636a416442674e5648513445466751556c5739640a7a62306234656c4153636e553944504f4156634c336c517744675944565230504151482f42415144416745474d42494741315564457745422f7751494d4159420a4166384341514177436759494b6f5a497a6a30454177494452774177524149675873566b6930772b6936565947573355462f32327561586530594a446a3155650a6e412b546a44316169356343494359623153416d4435786b66545670766f34556f79695359787244574c6d5552344349394e4b7966504e2b0a2d2d2d2d2d454e442043455254494649434154452d2d2d2d2d0a2d2d2d2d2d424547494e2043455254494649434154452d2d2d2d2d0a4d4949436a7a4343416a53674177494241674955496d554d316c71644e496e7a6737535655723951477a6b6e42717777436759494b6f5a497a6a3045417749770a614445614d4267474131554541777752535735305a5777675530645949464a766233516751304578476a415942674e5642416f4d45556c756447567349454e760a636e4276636d4630615739754d5251774567594456515148444174545957353059534244624746795954454c4d416b47413155454341774351304578437a414a0a42674e5642415954416c56544d423458445445344d4455794d5445774e4455784d466f58445451354d54497a4d54497a4e546b314f566f77614445614d4267470a4131554541777752535735305a5777675530645949464a766233516751304578476a415942674e5642416f4d45556c756447567349454e76636e4276636d46300a615739754d5251774567594456515148444174545957353059534244624746795954454c4d416b47413155454341774351304578437a414a42674e56424159540a416c56544d466b77457759484b6f5a497a6a3043415159494b6f5a497a6a3044415163445167414543366e45774d4449595a4f6a2f69505773437a61454b69370a314f694f534c52466857476a626e42564a66566e6b59347533496a6b4459594c304d784f346d717379596a6c42616c54565978465032734a424b357a6c4b4f420a757a43427544416642674e5648534d4547444157674251695a517a575770303069664f44744a5653763141624f5363477244425342674e5648523845537a424a0a4d45656752614244686b466f64485277637a6f764c324e6c636e52705a6d6c6a5958526c63793530636e567a6447566b63325679646d6c6a5a584d75615735300a5a577775593239744c306c756447567355306459556d397664454e424c6d526c636a416442674e564851344546675155496d554d316c71644e496e7a673753560a55723951477a6b6e4271777744675944565230504151482f42415144416745474d42494741315564457745422f7751494d4159424166384341514577436759490a4b6f5a497a6a3045417749445351417752674968414f572f35516b522b533943695344634e6f6f774c7550524c735747662f59693747535839344267775477670a41694541344a306c72486f4d732b586f356f2f7358364f39515778485241765a55474f6452513763767152586171493d0a2d2d2d2d2d454e442043455254494649434154452d2d2d2d2d0a00";
        (bytes memory reportData) = attestationVerifier.verifyAttestation(data);
        console.logBytes(reportData);
    }

    function deployProxyAdmin() public {
        string memory output = readJson();
        vm.startBroadcast();
        ProxyAdmin proxyAdmin = new ProxyAdmin();
        vm.stopBroadcast();
        vm.serializeAddress(output, "ProxyAdmin", address(proxyAdmin));
        saveJson(output);
    }

    function deployEmptyContract() public {
        string memory output = readJson();
        vm.startBroadcast();
        EmptyContract emptyContract = new EmptyContract();
        vm.stopBroadcast();
        vm.serializeAddress(output, "EmptyContract", address(emptyContract));
        saveJson(output);
    }

    function deployAttestationVerifier() public {
        address addr = vm.envAddress("AUTOMATA_DCAP_ATTESTATION");
        string memory output = readJson();
        vm.startBroadcast();
        AttestationVerifier attestationVerifier = new AttestationVerifier(addr);
        vm.stopBroadcast();
        vm.serializeAddress(output, "AttestationVerifier", address(attestationVerifier));
        saveJson(output);
    }

    function deployVerifier() public {
        uint256 version = vm.envUint("VERSION");
        require(version < 255, "version overflowed");

        uint256 attestValiditySecs = vm.envUint("ATTEST_VALIDITY_SECS");

        uint256 maxBlockNumberDiff = vm.envUint("MAX_BLOCK_NUMBER_DIFF");
        string memory output = readJson();
        ProxyAdmin proxyAdmin = ProxyAdmin(
            vm.parseJsonAddress(output, ".ProxyAdmin")
        );
        address attestationAddr = vm.parseJsonAddress(
            output,
            ".AttestationVerifier"
        );
        address verifierProxyAddr;

        vm.startBroadcast();
        TEELivenessVerifier verifierImpl = new TEELivenessVerifier();
        bytes memory initializeCall;
        if (
            vm.keyExistsJson(output, ".TEELivenessVerifierProxy") && version > 1
        ) {
            verifierProxyAddr = vm.parseJsonAddress(
                output,
                ".TEELivenessVerifierProxy"
            );
            console.log("reuse proxy");
            console.logAddress(verifierProxyAddr);
            console.logAddress(address(proxyAdmin));
        } else {
            console.log("Deploy new proxy");
            EmptyContract emptyContract = new EmptyContract();
            verifierProxyAddr = address(
                new TransparentUpgradeableProxy(
                    address(emptyContract),
                    address(proxyAdmin),
                    ""
                )
            );
        }
        if (version <= 1) {
            initializeCall = abi.encodeWithSelector(
                TEELivenessVerifier.initialize.selector,
                msg.sender,
                address(attestationAddr),
                maxBlockNumberDiff,
                attestValiditySecs
            );
        } else {
            initializeCall = abi.encodeWithSelector(
                TEELivenessVerifier.reinitialize.selector,
                version,
                msg.sender,
                address(attestationAddr),
                maxBlockNumberDiff,
                attestValiditySecs
            );
        }
        
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(verifierProxyAddr),
            address(verifierImpl),
            initializeCall
        );
        vm.stopBroadcast();

        vm.serializeAddress(
            output,
            "TEELivenessVerifierProxy",
            verifierProxyAddr
        );
        vm.serializeAddress(
            output,
            "TEELivenessVerifierImpl",
            address(verifierImpl)
        );
        saveJson(output);
    }

    function all() public {
        deploySigVerifyLib();
        deployPEMCertChainLib();
        deployAttestation();
        deployProxyAdmin();
        deployVerifier();
    }
}
