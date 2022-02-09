import { Provider, stark, shortString } from 'starknet';
const { getSelectorFromName } = stark;
import { readFileSync} from 'fs';

// Helper function to read input from the contract
const getContractAddress = () => {
  const data = readFileSync('./localhost.deployments.txt', 'utf8');
  const lines = data.trim().split("\n")
  const lastLine = lines[lines.length - 1]
  const address = lastLine.slice(0, 66) // Just pull out the address
  return(address)
}

getContractAddress();
const CONTRACT_ADDRESS = getContractAddress() // Grab contract address from deployments.txt so we don't have to copy/pasta every time
const network = "http://localhost:5001/";

const provider = new Provider({baseUrl: network})

const TOKEN_ID = "5";
const OWNER_ADDRESS = BigInt("0x062cdb5f547735b352813397a5d2621c950cd98c6ac606d6d8898b11d7bd7e96").toString(10);

// Set tokenId for #5
console.log('set address for #5')
const setTokenResponse = await provider.addTransaction({
  type: "INVOKE_FUNCTION",
  contract_address: CONTRACT_ADDRESS,
  entry_point_selector: getSelectorFromName("set_token_id"),
  calldata: [TOKEN_ID, OWNER_ADDRESS]
});

// Read dungeon metadata
const getTokenResponse = await provider.callContract({
  contract_address: CONTRACT_ADDRESS,
  entry_point_selector: getSelectorFromName("get_dungeon"),
  calldata: [TOKEN_ID]
}) 

console.log(`get_dungeon(): ${getTokenResponse.result}`); 
