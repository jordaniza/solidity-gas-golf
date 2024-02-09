// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IDeFiBridge {
	function initialize(address tournamentManagerAddress) external;

	function startERC20(
		uint256 amountOfTokens,
		address[] calldata erc20Addresses,
		address[] calldata defiProtocolAddresses
	) external;

	function startETH(
		uint amountOfETH,
		address[] calldata defiProtocolAddresses
	) external payable;

	function endERC20(
		uint256 amountOfTokens,
		address[] calldata erc20Addresses,
		address[] calldata defiProtocolAddresses
	) external returns (uint256[] memory);

	function endETH(
		uint amountOfETH,
		address[] calldata defiProtocolAddresses
	) external payable returns (uint256);
}
