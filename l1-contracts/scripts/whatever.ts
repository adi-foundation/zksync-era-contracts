// hardhat import should be the first import in the file
// eslint-disable-next-line @typescript-eslint/no-unused-vars
import * as hardhat from "hardhat";
import { Command } from "commander";
import { Wallet } from "ethers";
import { Deployer } from "../src.ts/deploy";
import { formatUnits, parseUnits } from "ethers/lib/utils";
import { web3Provider, GAS_MULTIPLIER } from "./utils";
import { deployedAddressesFromEnv } from "../src.ts/deploy-utils";
import { ethTestConfig } from "../src.ts/utils";
import {
  // setInitialCutHash,
  // upgradeProverFix,
  // upgradeMainnetFix,
  transferTokensOnForkedNetwork,
} from "../src.ts/hyperchain-upgrade";

const provider = web3Provider();

async function main() {
  const program = new Command();

  // used for emergency operations.
  program.version("0.1.0").name("deploy").description("deploy L1 contracts");

  program
    .option("--private-key <private-key>")
    .option("--chain-id <chain-id>")
    .option("--gas-price <gas-price>")
    .option("--nonce <nonce>")
    .option("--owner-address <owner-address>")
    .option("--create2-salt <create2-salt>")
    .option("--print-file-path <print-file-path>")
    .option("--diamond-upgrade-init <version>")
    .option("--only-verifier")
    .action(async (cmd) => {
      const deployWallet = cmd.privateKey
        ? new Wallet(cmd.privateKey, provider)
        : Wallet.fromMnemonic(
            process.env.MNEMONIC ? process.env.MNEMONIC : ethTestConfig.mnemonic,
            "m/44'/60'/0'/0/1"
          ).connect(provider);
      console.log(`Using deployer wallet: ${deployWallet.address}`);

      const ownerAddress = cmd.ownerAddress ? cmd.ownerAddress : deployWallet.address;
      console.log(`Using owner address: ${ownerAddress}`);

      const gasPrice = cmd.gasPrice
        ? parseUnits(cmd.gasPrice, "gwei")
        : (await provider.getGasPrice()).mul(GAS_MULTIPLIER);
      console.log(`Using gas price: ${formatUnits(gasPrice, "gwei")} gwei`);

      const nonce = cmd.nonce ? parseInt(cmd.nonce) : await deployWallet.getTransactionCount();
      console.log(`Using nonce: ${nonce}`);

      // const create2Salt = cmd.create2Salt
      //   ? cmd.create2Salt
      //   : "0x0000000000000000000000000000000000000000000000000000000000000000";

      const deployer = new Deployer({
        deployWallet,
        addresses: deployedAddressesFromEnv(),
        ownerAddress,
        verbose: true,
      });

      // await upgradeMainnetFix(deployer, create2Salt, gasPrice);
      // await upgradeProverFix(deployer, create2Salt, gasPrice);
      // await setInitialCutHash(deployer);
      // await
      await transferTokensOnForkedNetwork(deployer);
    });

  await program.parseAsync(process.argv);
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error("Error:", err);
    process.exit(1);
  });

// const failedTokens = [
//   "0x97e3C21f27182498382f81e32fbe0ea3A0e3D79b",
//   "0x304645590f197d99fAD9fA1d05e7BcDc563E1378",
//   "0xfc448180d5254A55846a37c86146407Db48d2a36",
// ];

// const failedTokens2 = [0x304645590f197d99fAD9fA1d05e7BcDc563E1378,
// 0x5A520e593F89c908cd2bc27D928bc75913C55C42,
// 0xfc448180d5254A55846a37c86146407Db48d2a36,
// 0xd3843c6Be03520f45871874375D618b3C7923019]
