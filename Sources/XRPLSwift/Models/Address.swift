//
//  Address.swift
//  AnyCodable
//
//  Created by Mitch Lang on 2/15/20.
//

import Foundation

public enum AddressError: Error {
    case invalidAddress
    case checksumFails
}

public struct Address {
    var rAddress: String
    var tag: UInt32?
    var isTest: Bool
    var xAddress: String {
        return Address.encodeXAddress(rAddress: self.rAddress, tag: self.tag, test: self.isTest)
    }
    
    public init(rAddress: String, tag: UInt32? = nil, isTest: Bool = false) throws {
        if !SeedWallet.validate(address: rAddress) {
            throw AddressError.invalidAddress
        }
        self.rAddress = rAddress
        self.tag = tag
        self.isTest = false
    }
    
    public init(xAddress: String) throws {
        let data = Data(base58Decoding: xAddress)!
        let check = data.suffix(4).bytes
        let concatenated = data.prefix(31).bytes
        let tagBytes = concatenated[23...]
        let flags = concatenated[22]
        let prefix = concatenated[..<2]
        let accountID = concatenated[2..<22]
        let prefixedAccountID = Data([0x00]) + accountID
        let checksum = Data(prefixedAccountID).sha256().sha256().prefix(through: 3)
        let addrrssData = prefixedAccountID + checksum
        let address = String(base58Encoding: addrrssData)
                
        if check == [UInt8](Data(concatenated).sha256().sha256().prefix(through: 3)) {
            let data = Data(tagBytes)
            let _tag: UInt64 = data.withUnsafeBytes { $0.pointee }
            let tag: UInt32? = flags == 0x00 ? nil : UInt32(String(_tag))!
            
            if prefix == [0x05, 0x44] { // mainnet
                try self.init(rAddress: address, tag: tag)
                isTest = false
            } else if prefix == [0x04, 0x93] { // testnet
                try self.init(rAddress: address, tag: tag)
                isTest = true
            } else {
                throw AddressError.invalidAddress
            }
        } else {
            throw AddressError.checksumFails
        }
    }
    
    public func address() -> String {
        return self.rAddress
    }
    
    public static func decodeXAddress(xAddress: String) throws -> Address {
        return try self.init(xAddress: xAddress)
    }
    
    public static func encodeXAddress(rAddress: String, tag: UInt32? = nil, test: Bool = false ) -> String {
        let accountID = SeedWallet.accountID(for: rAddress)
        let prefix: [UInt8] = test ? [0x04, 0x93] : [0x05, 0x44]
        let flags: [UInt8] = tag == nil ? [0x00] : [0x01]
        let tag = tag == nil ? [UInt8](UInt64(0).data) : [UInt8](UInt64(tag!).data)
        let concatenated = prefix + accountID + flags + tag
        let check = [UInt8](Data(concatenated).sha256().sha256().prefix(through: 3))
        let concatenatedCheck: [UInt8] = concatenated + check
        return String(base58Encoding: Data(concatenatedCheck), alphabet: Base58String.xrpAlphabet)
    }
}
