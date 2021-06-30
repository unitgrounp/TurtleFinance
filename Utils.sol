pragma solidity ^0.8.5;

library Utils {

    function bytesToHexString(bytes memory bs) internal pure returns (string memory) {
        bytes memory tempBytes = new bytes(bs.length * 2);
        uint len = bs.length;
        for (uint i = 0; i < len; i++) {
            bytes1 b = bs[i];
            bytes1 nb = (b & 0xf0) >> 4;
            tempBytes[2 * i] = nb > 0x09 ? bytes1((uint8(nb) + 0x37)) : (nb | 0x30);
            nb = (b & 0x0f);
            tempBytes[2 * i + 1] = nb > 0x09 ? bytes1((uint8(nb) + 0x37)) : (nb | 0x30);
        }
        return string(tempBytes);
    }


    function char(bytes1 b) internal view returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    function toAsciiString(address x) internal view returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint(uint160(x)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(s);
    }

    function functionCall(address addr, bytes memory data, string memory errMsg) internal {
        (bool success, bytes memory retData) = addr.call(data);
        require(success, string(abi.encodePacked(
                errMsg,
                ", addr: 0x", toAsciiString(addr),
                ", data: 0x", bytesToHexString(data),
                ", return: 0x", bytesToHexString(retData)
            )));
    }
}
