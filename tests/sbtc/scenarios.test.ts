import { describe, expect, it } from "vitest";
import { boolCV, Cl, principalCV, uintCV } from "@stacks/transactions";
import { betty, constructDao, metadataHash, passCoreProposal, setupSimnet, sbtcToken, wallace, deployer, alice, bob, tom, developer, annie } from "../helpers";
import { bufferFromHex } from "@stacks/transactions/dist/cl";
import { generateMerkleProof, generateMerkleTreeUsingStandardPrincipal, proofToClarityValue } from "../gating/gating";
import { resolveUndisputed } from "../predictions/helpers_staking";

const simnet = await setupSimnet();

/*
  The test below is an example. Learn more in the clarinet-sdk readme:
  https://github.com/hirosystems/clarinet/blob/develop/components/clarinet-sdk/README.md
*/

describe("check actual claims vs expected for some scenarios", () => {
  it("Alice stake 100STX on YES, market resolves yes", async () => {
    constructDao(simnet);
    let response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "create-market",
      [
        Cl.uint(0),
        Cl.principal(sbtcToken),
        Cl.bufferFromHex(metadataHash()), 
        Cl.list([]),
      ],
      deployer
    );
    expect(response.result).toEqual(Cl.ok(Cl.uint(0)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "predict-yes-stake",
      [Cl.uint(0), Cl.uint(100000000n), Cl.principal(sbtcToken)], 
      alice
    );
    expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    await resolveUndisputed(0, true);

    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "claim-winnings",
      [Cl.uint(0), Cl.principal(sbtcToken)],
      alice
    );
    expect(response.result).toEqual(Cl.ok(Cl.uint(96040000n)));
  });

  it("Alice stakes 100STX on yes, Bob 100STX on NO market resolves yes", async () => {
    constructDao(simnet);
    let response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "create-market",
      [
        Cl.uint(0),
        Cl.principal(sbtcToken),
        Cl.bufferFromHex(metadataHash()),
        Cl.list([]),
      ],
      deployer
    );
    expect(response.result).toEqual(Cl.ok(Cl.uint(0)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "predict-yes-stake",
      [Cl.uint(0), Cl.uint(100000000n), Cl.principal(sbtcToken)],
      alice
    );
    expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "predict-no-stake",
      [Cl.uint(0), Cl.uint(100000000n), Cl.principal(sbtcToken)],
      bob
    );
    expect(response.result).toEqual(Cl.ok(Cl.bool(true)));

    await resolveUndisputed(0, true);

    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "claim-winnings",
      [Cl.uint(0), Cl.principal(sbtcToken)],
      alice
    );
    expect(response.result).toEqual(Cl.ok(Cl.uint(192080000n)));

    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "claim-winnings",
      [Cl.uint(0), Cl.principal(sbtcToken)],
      bob
    );
    expect(response.result).toEqual(Cl.error(Cl.uint(10006)));
  });

  it("Alice stakes 100 STX on YES, Bob stakes 50 STX on YES, Tom stakes 200 STX on NO, Annie stakes 20 STX on NO, market resolves NO", async () => {
    constructDao(simnet);
    await passCoreProposal(`bdp001-gating`);
    const allowedCreators = [alice, bob, tom, betty, wallace];
    const { tree, root } = generateMerkleTreeUsingStandardPrincipal(allowedCreators);
    let merdat = generateMerkleProof(tree, alice);
    let response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "create-market",
      [
        Cl.uint(0),
        Cl.principal(sbtcToken),
        Cl.bufferFromHex(metadataHash()),
        proofToClarityValue(merdat.proof),
      ], 
      alice
    );
    expect(response.result).toEqual(Cl.ok(Cl.uint(0)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "predict-yes-stake",
      [Cl.uint(0), Cl.uint(100000000n), Cl.principal(sbtcToken)],
      alice
    );
    expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "predict-yes-stake",
      [Cl.uint(0), Cl.uint(50000000n), Cl.principal(sbtcToken)],
      bob
    );
    expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "predict-no-stake",
      [Cl.uint(0), Cl.uint(200000000), Cl.principal(sbtcToken)],
      developer
    );
    expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "predict-no-stake",
      [Cl.uint(0), Cl.uint(20000000), Cl.principal(sbtcToken)],
      annie
    );
    expect(response.result).toEqual(Cl.ok(Cl.bool(true)));

    expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
    await resolveUndisputed(0, false);
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "claim-winnings",
      [Cl.uint(0), Cl.principal(sbtcToken)],
      alice
    );
    expect(response.result).toEqual(Cl.error(Cl.uint(10006)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "claim-winnings",
      [Cl.uint(0), Cl.principal(sbtcToken)],
      bob
    );
    let stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
    console.log(
      "contractBalance: " +
        stxBalances?.get(deployer + ".bde023-market-staked-predictions")
    );
    expect(response.result).toEqual(Cl.error(Cl.uint(10006)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "claim-winnings",
      [Cl.uint(0), Cl.principal(sbtcToken)],
      developer
    );
    expect(response.result).toEqual(Cl.ok(Cl.uint(323043636n)));
    response = await simnet.callPublicFn(
      "bde023-market-staked-predictions",
      "claim-winnings",
      [Cl.uint(0), Cl.principal(sbtcToken)],
      annie
    );
    expect(response.result).toEqual(Cl.ok(Cl.uint(32304364n)));
    stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
    console.log(
      "contractBalance: " +
        stxBalances?.get(deployer + ".bde023-market-staked-predictions")
    );
  });
});

it("Alice stakes 100 STX on YES, Bob stakes 50 STX on YES, Tom stakes 200 STX on NO, Annie stakes 20 STX on NO, market resolves NO", async () => {
    constructDao(simnet);
    let response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "create-market",
    [
      Cl.uint(0),
      Cl.principal(sbtcToken),
      Cl.bufferFromHex(metadataHash()),
      Cl.list([]),
    ],
    deployer
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(0)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(0), Cl.uint(100000000000n), Cl.principal(sbtcToken)],
    alice
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(0), Cl.uint(5000000000000n), Cl.principal(sbtcToken)],
    bob
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(0), Cl.uint(20000000000000), Cl.principal(sbtcToken)],
    developer
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(0), Cl.uint(20000000000000), Cl.principal(sbtcToken)],
    annie
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));

  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  await resolveUndisputed(0, false);
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(0), Cl.principal(sbtcToken)],
    alice
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(96040000000n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(0), Cl.principal(sbtcToken)],
    bob
  );
  let stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
  console.log(
    "contractBalance: " +
      stxBalances?.get(deployer + ".bde023-market-staked-predictions")
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(4802000000000n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(0), Cl.principal(sbtcToken)],
    developer
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(19208000000000n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(0), Cl.principal(sbtcToken)],
    annie
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(19208000000000n)));
  stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
  console.log(
    "contractBalance: " +
      stxBalances?.get(deployer + ".bde023-market-staked-predictions")
  );
});

it("Alice stakes 100 STX on YES, Bob stakes 50 STX on YES, Tom stakes 200 STX on NO, Annie stakes 20 STX on NO, market resolves NO", async () => {
    constructDao(simnet);
  let response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "create-market",
    [
      Cl.uint(0),
      Cl.principal(sbtcToken),
      Cl.bufferFromHex(metadataHash()),
      Cl.list([]),
    ],
    deployer
  );
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "create-market",
    [
      Cl.uint(0),
      Cl.principal(sbtcToken),
      Cl.bufferFromHex(metadataHash()),
      Cl.list([]),
    ],
    deployer
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(1)));

  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(0), Cl.uint(100000000000n), Cl.principal(sbtcToken)],
    alice
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions", 
    "predict-no-stake",
    [Cl.uint(0), Cl.uint(5000000000000n), Cl.principal(sbtcToken)],
    bob
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(0), Cl.uint(20000000000000), Cl.principal(sbtcToken)],
    developer
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions", 
    "predict-no-stake",
    [Cl.uint(0), Cl.uint(20000000000000), Cl.principal(sbtcToken)],
    annie
  ); 
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
 
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(1), Cl.uint(1000000n), Cl.principal(sbtcToken)],
    alice
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(1), Cl.uint(5000000000000n), Cl.principal(sbtcToken)],
    bob
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(1), Cl.uint(20000000000000), Cl.principal(sbtcToken)],
    developer
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "predict-no-stake",
    [Cl.uint(1), Cl.uint(20000000000000), Cl.principal(sbtcToken)],
    annie
  );
  expect(response.result).toEqual(Cl.ok(Cl.bool(true)));

  await resolveUndisputed(0, false);
  await resolveUndisputed(1, false);

  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(0), Cl.principal(sbtcToken)],
    alice
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(96040000000n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(0), Cl.principal(sbtcToken)],
    bob
  );
  let stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
  console.log(
    "contractBalance: " +
      stxBalances?.get(deployer + ".bde023-market-staked-predictions")
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(4802000000000n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(0), Cl.principal(sbtcToken)],
    developer
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(19208000000000n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(0), Cl.principal(sbtcToken)],
    annie
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(19208000000000n)));
  stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
  console.log(
    "contractBalance: " +
      stxBalances?.get(deployer + ".bde023-market-staked-predictions")
  );

  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(1), Cl.principal(sbtcToken)],
    alice
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(960400n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(1), Cl.principal(sbtcToken)],
    bob
  );
  stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
  console.log(
    "contractBalance: " +
      stxBalances?.get(deployer + ".bde023-market-staked-predictions")
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(4802000000000n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(1), Cl.principal(sbtcToken)],
    developer
  );
  let data = await simnet.callReadOnlyFn(
    "bde023-market-staked-predictions",
    "get-market-data",
    [Cl.uint(0)],
    alice
  );
  expect(data.result).toMatchObject(
    Cl.some(
      Cl.tuple({
        creator: principalCV(deployer),
        "market-type": uintCV(0),
        "market-data-hash": bufferFromHex(metadataHash()),
        "yes-pool": uintCV(0n),
        "no-pool": uintCV(44198000000000n),
        // "resolution-burn-height": uintCV(0),
        "resolution-state": uintCV(3),
        concluded: boolCV(true),
        outcome: boolCV(false),
      })
    )
  );
  data = await simnet.callReadOnlyFn(
    "bde023-market-staked-predictions",
    "get-stake-balances",
    [Cl.uint(1), Cl.principal(annie)],
    annie
  );
  expect(data.result).toEqual(
    Cl.some(
      Cl.tuple({
        "yes-amount": uintCV(0),
        "no-amount": uintCV(19600000000000n),
      })
    )
  );
  stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
  console.log(
    "contractBalance 32: " +
      stxBalances?.get(deployer + ".bde023-market-staked-predictions")
  );

  expect(response.result).toEqual(Cl.ok(Cl.uint(19208000000000n)));
  response = await simnet.callPublicFn(
    "bde023-market-staked-predictions",
    "claim-winnings",
    [Cl.uint(1), Cl.principal(sbtcToken)],
    annie
  );
  expect(response.result).toEqual(Cl.ok(Cl.uint(19208000000000n)));
  stxBalances = simnet.getAssetsMap().get("STX"); // Replace if contract's principal
  console.log(
    "contractBalance 32: " +
      stxBalances?.get(deployer + ".bde023-market-staked-predictions")
  );
});
