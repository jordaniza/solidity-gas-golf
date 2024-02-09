// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./interfaces/Erc20.sol";
import "./interfaces/IDeFiBridge.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TournamentManager is Ownable(msg.sender) {
	//------------------------------------------Storage-------------------------------------------------------------
	// Struct TournamentData
	struct TournamentData {
		uint16 ID;
		uint8 minParticipants;
		uint16 maxParticipants;
		mapping(address => bool) isParticipant;
		uint16 numParticipants;
		uint256 enrollmentAmount; // in Wei
		address[] acceptedTokens;
		uint256[] totalRewardAmount; // Only rewards
		uint64 initDate;
		uint64 endDate;
		address deFiBridgeAddress;
		address[] deFiProtocolAddresses;
		bytes32 resultsSpongeHash;
		bytes32 merkleRoot;
		bool aborted;
	}

	// Tournament tournament;
	// Array tournaments
	TournamentData[] public tournaments;
	// ID IDcounter para el ID del torneo
	uint16 idCounter;

	//--------------------------------------------Events------------------------------------------------------
	event TournamentCreated(
		uint16 indexed tournamentID,
		uint64 initData,
		uint64 endDate,
		address deFiBridgeAddress
	);
	event Enroll(
		uint16 indexed tournamentID,
		address indexed user,
		uint16 numParticipants,
		uint256 totalCollectedAmount
	);
	event ResultCreated(
		uint16 indexed tournamentID,
		address indexed player,
		uint scoreNumber
	);

	//------------------------------------------Functions-----------------------------------------------------

	function createTournament(
		uint16 _maxParticipants,
		uint8 _minParticipants,
		uint256 _enrollmentAmount,
		address[] calldata _acceptedTokens,
		uint64 _initDate,
		uint64 _endDate,
		address _deFiBridgeToClone,
		address[] calldata _deFiProtocolAddresses
	) external onlyOwner {
		tournaments.push();
		TournamentData storage newTournament = tournaments[idCounter];

		newTournament.ID = idCounter;

		newTournament.minParticipants = _minParticipants;
		newTournament.maxParticipants = _maxParticipants;

		newTournament.enrollmentAmount = _enrollmentAmount;
		for (uint8 i = 0; i < _acceptedTokens.length; i++) {
			newTournament.acceptedTokens.push(_acceptedTokens[i]);
		}

		newTournament.initDate = _initDate;
		newTournament.endDate = _endDate;

		newTournament.deFiBridgeAddress = Clones.clone(_deFiBridgeToClone);
		IDeFiBridge(newTournament.deFiBridgeAddress).initialize(address(this));

		for (uint8 i = 0; i < _deFiProtocolAddresses.length; i++) {
			newTournament.deFiProtocolAddresses.push(_deFiProtocolAddresses[i]);
		}
		idCounter++;

		emit TournamentCreated(
			newTournament.ID,
			newTournament.initDate,
			newTournament.endDate,
			newTournament.deFiBridgeAddress
		);
	}

	function enrollWithERC20(uint16 idTournament) external {
		TournamentData storage selectedTournament = tournaments[idTournament];

		// Ensure that the enrollment period is still open.
		require(
			block.timestamp <= selectedTournament.initDate,
			"Enrollment period has ended."
		);

		require(
			selectedTournament.isParticipant[msg.sender] == false,
			"Address is already enrolled in this tournament."
		);
		require(
			selectedTournament.numParticipants <
				selectedTournament.maxParticipants,
			"Tournament full."
		);

		for (uint8 i = 0; i < selectedTournament.acceptedTokens.length; i++) {
			require(
				ERC20(selectedTournament.acceptedTokens[i]).balanceOf(
					msg.sender
				) >= selectedTournament.enrollmentAmount,
				"Insufficient balance."
			);
			ERC20(selectedTournament.acceptedTokens[i]).transferFrom(
				msg.sender,
				address(this),
				selectedTournament.enrollmentAmount
			);
		}

		selectedTournament.isParticipant[msg.sender] = true;

		selectedTournament.numParticipants++;

		uint256 totalCollectedAmount = selectedTournament.numParticipants *
			selectedTournament.enrollmentAmount;
		emit Enroll(
			selectedTournament.ID,
			msg.sender,
			selectedTournament.numParticipants,
			totalCollectedAmount
		);
	}

	function enrollWithETH(uint16 idTournament) external payable {
		TournamentData storage selectedTournament = tournaments[idTournament];
		require(
			block.timestamp <= selectedTournament.initDate,
			"Enrollment period has ended."
		);
		require(
			selectedTournament.isParticipant[msg.sender] == false,
			"Address is already enrolled in this tournament."
		);
		require(
			selectedTournament.numParticipants <
				selectedTournament.maxParticipants,
			"Tournament is full."
		);
		require(
			msg.value == selectedTournament.enrollmentAmount,
			"Incorrect or insufficient ETH value."
		);

		// Assign the enrollment amount to the participant.
		selectedTournament.isParticipant[msg.sender] = true;

		uint256 totalCollectedAmount = selectedTournament.numParticipants *
			selectedTournament.enrollmentAmount;
		selectedTournament.numParticipants++;

		emit Enroll(
			selectedTournament.ID,
			msg.sender,
			selectedTournament.numParticipants,
			totalCollectedAmount
		);
	}

	function startERC20Tournament(uint16 idTournament) external onlyOwner {
		TournamentData storage selectedTournament = tournaments[idTournament];

		// Ensure that the tournament can only start after the initiation date.
		require(
			block.timestamp > selectedTournament.initDate,
			"Tournament cannot start before the initiation date."
		);

		if (
			selectedTournament.numParticipants <
			selectedTournament.minParticipants
		) {
			selectedTournament.aborted = true;
			return;
		}

		for (uint8 i = 0; i < selectedTournament.acceptedTokens.length; i++) {
			ERC20(selectedTournament.acceptedTokens[i]).transfer(
				selectedTournament.deFiBridgeAddress,
				selectedTournament.enrollmentAmount *
					selectedTournament.numParticipants
			);
		}

		IDeFiBridge(selectedTournament.deFiBridgeAddress).startERC20(
			selectedTournament.enrollmentAmount *
				selectedTournament.numParticipants,
			selectedTournament.acceptedTokens,
			selectedTournament.deFiProtocolAddresses
		);
	}

	function startETHTournament(
		uint16 idTournament
	) external payable onlyOwner {
		TournamentData storage selectedTournament = tournaments[idTournament];

		// Ensure that the tournament can only start after the initiation date.
		require(
			block.timestamp > selectedTournament.initDate,
			"Tournament cannot start before the initiation date."
		);

		if (
			selectedTournament.numParticipants <
			selectedTournament.minParticipants
		) {
			selectedTournament.aborted = true;
		} else {
			(bool success, ) = selectedTournament.deFiBridgeAddress.call{
				value: selectedTournament.numParticipants *
					selectedTournament.enrollmentAmount
			}(
				abi.encodeWithSignature(
					"startETH(uint256,address[] calldata)",
					selectedTournament.numParticipants *
						selectedTournament.enrollmentAmount,
					selectedTournament.deFiProtocolAddresses
				)
			);
			require(success, "Call to DeFiBridge failed.");
		}
	}

	function abortERC20(uint16 idTournament) external {
		TournamentData storage abortedTournament = tournaments[idTournament];
		require(abortedTournament.aborted, "Tournament must be aborted.");

		for (uint8 i = 0; i < abortedTournament.acceptedTokens.length; i++) {
			ERC20(abortedTournament.acceptedTokens[i]).transfer(
				address(msg.sender),
				abortedTournament.enrollmentAmount
			);
		}

		// Set the participant's balance to zero.
		abortedTournament.isParticipant[msg.sender] = false;
	}

	function abortETH(uint16 idTournament) external payable {
		TournamentData storage abortedTournament = tournaments[idTournament];
		require(abortedTournament.aborted, "Tournament must be aborted.");

		// Attempt to transfer any remaining ETH to the user.
		(bool transferSuccess, ) = payable(msg.sender).call{
			value: abortedTournament.enrollmentAmount
		}("");
		require(transferSuccess, "ETH transfer failed.");

		// Set the participant's balance to zero.
		abortedTournament.isParticipant[msg.sender] = false;
	}

	function endERC20Tournament(
		uint16 idTournament,
		bytes calldata resultsBytes, // Each element is 52 bytes: 20 for the address and 32 for the score.
		uint16[] calldata positions
	) public onlyOwner {
		TournamentData storage selectedTournament = tournaments[idTournament];
		require(
			block.timestamp > selectedTournament.endDate,
			"Tournament cannot be finished before the end date."
		);
		createLeaderBoardMerkleTree(idTournament, resultsBytes, positions);

		// End the tournament with the DeFi Bridge and get the rewards.
		uint256[] memory deFiBridgeRewards = IDeFiBridge(
			selectedTournament.deFiBridgeAddress
		).endERC20(
				selectedTournament.numParticipants *
					selectedTournament.enrollmentAmount,
				selectedTournament.acceptedTokens,
				selectedTournament.deFiProtocolAddresses
			);

		for (uint8 i = 0; i < selectedTournament.acceptedTokens.length; i++) {
			// Calculate and set the player's rewards.
			uint256 tournamentReward = (deFiBridgeRewards[i] * 8) / 10;
			selectedTournament.totalRewardAmount.push(tournamentReward);

			// Transfer the remaining rewards to the owner.
			ERC20(selectedTournament.acceptedTokens[i]).transfer(
				msg.sender,
				(deFiBridgeRewards[i] * 2) / 10
			);
		}
	}

	function endETHTournament(
		uint16 idTournament,
		bytes calldata resultsBytes, // Each element is 52 bytes: 20 for the address and 32 for the score.
		uint16[] calldata positions
	) public onlyOwner {
		TournamentData storage selectedTournament = tournaments[idTournament];

		require(
			block.timestamp > selectedTournament.endDate,
			"Tournament cannot be finished before the end date."
		);

		createLeaderBoardMerkleTree(idTournament, resultsBytes, positions);

		uint256 deFiBridgeReward = IDeFiBridge(
			selectedTournament.deFiBridgeAddress
		).endETH(
				selectedTournament.numParticipants *
					selectedTournament.enrollmentAmount,
				selectedTournament.deFiProtocolAddresses
			);

		selectedTournament.totalRewardAmount.push((deFiBridgeReward * 8) / 10);

		(bool callSuccess, ) = payable(msg.sender).call{
			value: (deFiBridgeReward * 2) / 10
		}("");
		require(callSuccess, "ETH transfer failed.");
	}

	function verifyAndClaim(
		uint16 idTournament,
		bool[] calldata isLeft,
		uint16 position,
		bytes32[] calldata merkleProof
	) public {
		TournamentData storage endedTournament = tournaments[idTournament];

		require(
			endedTournament.isParticipant[msg.sender],
			"You are not participating in this tournament, or you already claimed your reward."
		);

		if (position == 2 ** 16 - 1) {
			if (endedTournament.acceptedTokens.length == 0) {
				(bool success, ) = msg.sender.call{
					value: endedTournament.enrollmentAmount
				}("");
				require(success, "Failed to claim Ether.");
				endedTournament.isParticipant[msg.sender] = false;
				return;
			}

			for (uint i = 0; i < endedTournament.acceptedTokens.length; i++) {
				ERC20(endedTournament.acceptedTokens[i]).transfer(
					msg.sender,
					endedTournament.enrollmentAmount
				);
			}
			endedTournament.isParticipant[msg.sender] = false;
			return;
		}

		bytes32 merkleLeaf = keccak256(abi.encodePacked(msg.sender, position));
		for (uint256 i = 0; i < isLeft.length; i++) {
			if (isLeft[i]) {
				merkleLeaf = keccak256(
					abi.encodePacked(merkleProof[i], merkleLeaf)
				);
			} else {
				merkleLeaf = keccak256(
					abi.encodePacked(merkleLeaf, merkleProof[i])
				);
			}
		}

		require(
			merkleLeaf == endedTournament.merkleRoot,
			"Merkle proof verification failed."
		);

		uint256[] memory payouts = getPayoutStructure(
			endedTournament.numParticipants
		);

		if (endedTournament.acceptedTokens.length == 0) {
			uint256 reward = (endedTournament.totalRewardAmount[0] *
				payouts[position]) / 100;

			(bool success, ) = msg.sender.call{
				value: reward + endedTournament.enrollmentAmount
			}("");
			require(success, "Failed to send Ether.");
		} else {
			for (uint i = 0; i < endedTournament.acceptedTokens.length; i++) {
				uint256 reward = (endedTournament.totalRewardAmount[i] *
					payouts[position]) / 100;

				ERC20(endedTournament.acceptedTokens[i]).transfer(
					msg.sender,
					reward + endedTournament.enrollmentAmount
				);
			}
		}
		endedTournament.isParticipant[msg.sender] = false;
	}

	function getPayoutStructure(
		uint16 numParticipants
	) internal pure returns (uint256[] memory) {
		uint256[] memory payout = new uint256[](numParticipants);
		if (numParticipants <= 10) {
			payout[0] = 70;
			if (numParticipants == 2) {
				payout[1] = 30;
			}
			return payout;
		} else if (numParticipants <= 31) {
			payout[0] = 60;
			payout[1] = 30;
			payout[2] = 10;
			return payout;
		} else if (numParticipants <= 63) {
			payout[0] = 50;
			payout[1] = 25;
			payout[2] = 15;
			payout[3] = 10;
			return payout;
		} else if (numParticipants <= 80) {
			payout[0] = 45;
			payout[1] = 25;
			payout[2] = 14;
			payout[3] = 10;
			payout[4] = 3;
			payout[5] = 3;
			return payout;
		} else {
			payout[0] = 44;
			payout[1] = 22;
			payout[2] = 12;
			payout[3] = 8;
			payout[4] = 5;
			payout[5] = 5;
			payout[6] = 2;
			payout[7] = 2;
			return payout;
		}
	}

	// Results are the concatenation of the BYTES of (address, score) for each player
	function setResult(
		uint16 idTournament,
		address player,
		uint256 newScore
	) external {
		// Sponge Hash with previous resultsSpongeHash and new result (bytes(addressPlayer, scorePlayer)) -> hash(historic_results,new_results)
		// TODO require accepted source 
		require(
			block.timestamp >= tournaments[idTournament].initDate,
			"Tournament hasn't started yet."
		);
		tournaments[idTournament].resultsSpongeHash = keccak256(
			abi.encodePacked(
				tournaments[idTournament].resultsSpongeHash,
				player,
				newScore
			)
		);

		emit ResultCreated(idTournament, player, newScore);
	}

	function createLeaderBoardMerkleTree(
		uint16 idTournament,
		bytes calldata bytesResultsData, // Each element is 52 bytes: 20 for the address and 32 for the score.
		uint16[] calldata positions
	) private {
		require(
			block.timestamp >= tournaments[idTournament].endDate,
			"Tournament hasn't ended yet."
		);

		uint16 initialLength = uint16(positions.length);
		bytes32[] memory leaderboardHash = new bytes32[](initialLength);
		bytes32 lastScore = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF; // Initialize with the largest possible score.
		bytes32 backendSpongeHash;

		for (uint16 i = 0; i < initialLength; i++) {
			backendSpongeHash = keccak256(
				abi.encodePacked(
					backendSpongeHash,
					bytesResultsData[i * 52:(i + 1) * 52]
				)
			);
			leaderboardHash[i] = keccak256(
				abi.encodePacked(
					bytesResultsData[positions[i] * 52:positions[i] * 52 + 20],
					i
				)
			);

			require(
				bytes32(
					bytesResultsData[positions[i] * 52 + 20:(positions[i] + 1) *
						52]
				) <= lastScore,
				"Data corrupted: incorrect player classification."
			);
			lastScore = bytes32(
				bytesResultsData[positions[i] * 52 + 20:(positions[i] + 1) * 52]
			);
		}

		require(
			backendSpongeHash == tournaments[idTournament].resultsSpongeHash,
			"Data corrupted: bad spongeHash recreation."
		);

		uint16 levelLeaves = initialLength;
		while (levelLeaves > 1) {
			uint16 j = 0;
			for (uint16 i = 0; i < levelLeaves; i += 2) {
				if (i + 1 == levelLeaves) {
					leaderboardHash[j] = leaderboardHash[i];
				} else {
					leaderboardHash[j] = keccak256(
						abi.encodePacked(
							leaderboardHash[i],
							leaderboardHash[i + 1]
						)
					);
				}
				j++;
			}
			levelLeaves = (levelLeaves / 2) + (levelLeaves % 2);
		}

		tournaments[idTournament].merkleRoot = leaderboardHash[0];
	}

	// Getter function for participants of a tournament
	function getParticipants(
		uint16 idTournament,
		address participantAddress
	) public view returns (bool) {
		require(idTournament < tournaments.length, "Invalid tournament ID");
		return tournaments[idTournament].isParticipant[participantAddress];
	}

	// Getter function for accepted tokens of a tournament
	function getAcceptedTokens(
		uint16 idTournament
	) public view returns (address[] memory) {
		require(idTournament < tournaments.length, "Invalid tournament ID");
		return tournaments[idTournament].acceptedTokens;
	}

	// Getter function for retrieve the Positions of the structs for ERC20 and ETH tournaments
	function getTournamentIds()
		public
		view
		returns (
			uint[] memory ethereumTournamentIDs,
			uint[] memory erc20TournamentIDs
		)
	{
		uint[] memory ethereumIDs = new uint[](tournaments.length);
		uint[] memory erc20IDs = new uint[](tournaments.length);
		uint ethereumCount = 0;
		uint erc20Count = 0;

		for (uint16 i = 0; i < tournaments.length; i++) {
			if (tournaments[i].acceptedTokens.length == 0) {
				ethereumIDs[ethereumCount] = tournaments[i].ID;
				ethereumCount++;
			} else {
				erc20IDs[erc20Count] = tournaments[i].ID;
				erc20Count++;
			}
		}

		// Return the correctly sized arrays
		ethereumTournamentIDs = new uint[](ethereumCount);
		erc20TournamentIDs = new uint[](erc20Count);

		for (uint i = 0; i < ethereumCount; i++) {
			ethereumTournamentIDs[i] = ethereumIDs[i];
		}

		for (uint i = 0; i < erc20Count; i++) {
			erc20TournamentIDs[i] = erc20IDs[i];
		}

		return (ethereumTournamentIDs, erc20TournamentIDs);
	}

	function getMerkleRoot(uint16 idTournament) public view returns (bytes32) {
		return tournaments[idTournament].merkleRoot;
	}

	// Getter function for participants of a tournament
	function getSpongeHash(uint16 idTournament) public view returns (bytes32) {
		return tournaments[idTournament].resultsSpongeHash;
	}
}
