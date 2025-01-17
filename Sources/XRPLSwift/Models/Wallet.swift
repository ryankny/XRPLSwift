//
//  Account.swift
//  XRPLSwift
//
//  Created by Mitch Lang on 5/10/19.
//

import Foundation

let HASH_CHANNEL_SIGN: [UInt8] = [0x43,0x4C,0x4D, 0x00]

public enum SeedError: Error {
    case invalidSeed
}

public enum KeyPairError: Error {
    case invalidPrivateKey
}

public enum SeedType {
    case ed25519
    case secp256k1

    var algorithm: SigningAlgorithm.Type {
        switch self {
        case .ed25519:
            return ED25519.self
        case .secp256k1:
            return SECP256K1.self
        }
    }

}

public protocol Wallet {
    var privateKey: String {get}
    var publicKey: String {get}
    var address: String {get}
    var accountID: [UInt8] {get}
    init()
    static func deriveAddress(publicKey: String) -> String
    static func accountID(for address: String) ->  [UInt8]
    static func validate(address: String) -> Bool
}

extension Wallet {
    public var accountID: [UInt8] {
        let accountID = RIPEMD160.hash(message: Data(hex: self.publicKey).sha256())
        return [UInt8](accountID)
    }
    /// Derive a standard XRP address from a public key.
    ///
    /// - Parameter publicKey: hexadecimal public key
    /// - Returns: standard XRP address encoded using XRP alphabet
    ///
    public static func deriveAddress(publicKey: String) -> String {
        let accountID = RIPEMD160.hash(message: Data(hex: publicKey).sha256())
        let prefixedAccountID = Data([0x00]) + accountID
        let checksum = Data(prefixedAccountID).sha256().sha256().prefix(through: 3)
        let addrrssData = prefixedAccountID + checksum
        let address = String(base58Encoding: addrrssData)
        return address
    }
    
    public static func accountID(for address: String) ->  [UInt8] {
        let data = Data(base58Decoding: address)!
        let withoutCheck = data.prefix(data.count-4)
        let withoutPrefix = withoutCheck.suffix(from: 1)
        return withoutPrefix.bytes
    }
    
    /// Validates a String is a valid XRP address.
    ///
    /// - Parameter address: address encoded using XRP alphabet
    /// - Returns: true if valid
    ///
    public static func validate(address: String) -> Bool {
        if address.first != "r" {
            return false
        }
        if address.count < 25 || address.count > 35 {
            return false
        }
        if let _addressData = Data(base58Decoding: address) {
            var addressData = [UInt8](_addressData)
            // FIXME: base58Decoding
            addressData[0] = 0
            let accountID = [UInt8](addressData.prefix(addressData.count-4))
            let checksum = [UInt8](addressData.suffix(4))
            let _checksum = [UInt8](Data(accountID).sha256().sha256().prefix(through: 3))
            if checksum == _checksum {
                return true
            }
        }
        return false
    }
}

public class MnemonicWallet: Wallet {
    
    public var privateKey: String
    public var publicKey: String
    public var address: String
    public var mnemonic: String
    
    required public convenience init() {
        let mnemonic = try! Bip39Mnemonic.create()
        try! self.init(mnemonic: mnemonic)
    }
    
    /// Generates an Wallet from an mnemonic string.
    ///
    /// - Parameter mnemonic: mnemonic phrase .
    /// - Throws: SeedError
    public convenience init(mnemonic: String, account: UInt32 = 0, change: UInt32 = 0, addressIndex: UInt32 = 0) throws {
        let seed = Bip39Mnemonic.createSeed(mnemonic: mnemonic)
        let privateKey = PrivateKey(seed: seed, coin: .bitcoin)
        
        // BIP44 key derivation
        // m/44'
        let purpose = privateKey.derived(at: .hardened(44))
        // m/44'/144'
        let coinType = purpose.derived(at: .hardened(144))
        // m/44'/144'/0'
        let account = coinType.derived(at: .hardened(account))
        // m/44'/144'/0'/0
        let change = account.derived(at: .notHardened(change))
        // m/44'/144'/0'/0/0
        let firstPrivateKey = change.derived(at: .notHardened(addressIndex))
        
        var finalMasterPrivateKey = Data(repeating: 0x00, count: 33)
        finalMasterPrivateKey.replaceSubrange(1...firstPrivateKey.raw.count, with: firstPrivateKey.raw)
        let address = SeedWallet.deriveAddress(publicKey: firstPrivateKey.publicKey.hexadecimal)
        self.init(
            privateKey: finalMasterPrivateKey.hexadecimal,
            publicKey: firstPrivateKey.publicKey.hexadecimal,
            mnemonic: mnemonic,
            address: address
        )
    }
    
    private init(privateKey: String, publicKey: String, mnemonic: String, address: String) {
        self.privateKey = privateKey.uppercased()
        self.publicKey = publicKey.uppercased()
        self.mnemonic = mnemonic
        self.address = address
    }
    
    public static func generateRandomMnemonicWallet() throws -> Wallet {
        let mnemonic = try Bip39Mnemonic.create()
        return try MnemonicWallet(mnemonic: mnemonic)
    }
}

public class SeedWallet: Wallet {

    public var privateKey: String
    public var publicKey: String
    public var seed: String
    public var address: String
    
    public required convenience init() {
        let entropy = Entropy()
        self.init(entropy: entropy, type: .secp256k1)
    }

    public convenience init(type: SeedType = .secp256k1) {
        let entropy = Entropy()
        self.init(entropy: entropy, type: type)
    }
    
    private init(privateKey: String, publicKey: String, seed: String, address: String) {
        self.privateKey = privateKey
        self.publicKey = publicKey
        self.seed = seed
        self.address = address
    }

    private convenience init(entropy: Entropy, type: SeedType) {
        switch type {
        case .ed25519:
            let keyPair = try! ED25519.deriveKeyPair(seed: entropy.bytes)
            let publicKey = [0xED] + keyPair.publicKey.hexadecimal!
            let seed = try! SeedWallet.encodeSeed(entropy: entropy, type: .ed25519)
            let address = SeedWallet.deriveAddress(publicKey: publicKey.toHexString())
            self.init(privateKey: keyPair.privateKey, publicKey: publicKey.toHexString(), seed: seed, address: address)
        case .secp256k1:
            let keyPair = try! SECP256K1.deriveKeyPair(seed: entropy.bytes)
            let seed = try! SeedWallet.encodeSeed(entropy: entropy, type: .secp256k1)
            let address = SeedWallet.deriveAddress(publicKey: keyPair.publicKey)
            self.init(privateKey: keyPair.privateKey, publicKey: keyPair.publicKey, seed: seed, address: address)
        }
    }

    /// Generates an Wallet from an existing family seed.
    ///
    /// - Parameter seed: amily seed using XRP alphabet and standard format.
    /// - Throws: SeedError
    public convenience init(seed: String) throws {
        guard let bytes = try SeedWallet.decodeSeed(seed: seed) else {
            throw SeedError.invalidSeed
        }
        let entropy = Entropy(bytes: bytes)
        let type = seed.prefix(3) == "sEd" ? SeedType.ed25519 : SeedType.secp256k1
        self.init(entropy: entropy, type: type)
    }

    private static func encodeSeed(entropy: Entropy, type: SeedType) throws -> String {
        // [0x01, 0xE1, 0x4B] = sEd, [0x21] = s
        // see ripple/ripple-keypairs
        let version: [UInt8] = type == .ed25519 ? [0x01, 0xE1, 0x4B] : [0x21]
        let versionEntropy: [UInt8] = version + entropy.bytes
        let check = [UInt8](Data(versionEntropy).sha256().sha256().prefix(through: 3))
        let versionEntropyCheck: [UInt8] = versionEntropy + check
        return String(base58Encoding: Data(versionEntropyCheck), alphabet: Base58String.xrpAlphabet)
    }

    private static func decodeSeed(seed: String) throws -> [UInt8]? {
        // make sure seed will at least parse for checksum validation
        // FIXME: this needs work
        if seed.count < 10 || Data(base58Decoding: seed) == nil || seed.first != "s" {
            throw SeedError.invalidSeed
        }
        let versionEntropyCheck = [UInt8](Data(base58Decoding: seed)!)
        let check = Array(versionEntropyCheck.suffix(4))
        let versionEntropy = versionEntropyCheck.prefix(versionEntropyCheck.count-4)
        if check == [UInt8](Data(versionEntropy).sha256().sha256().prefix(through: 3)) {
            if versionEntropy[0] == 0x21 {
                // secp256k1
                let entropy = Array(versionEntropy.suffix(versionEntropy.count-1))
                return entropy
            } else if versionEntropy[0] == 0x01 && versionEntropy[1] == 0xE1 && versionEntropy[2] == 0x4B {
                // ed25519
                let entropy = Array(versionEntropy.suffix(versionEntropy.count-3))
                return entropy
            }
        }
        throw SeedError.invalidSeed
    }


    public static func getSeedTypeFrom(publicKey: String) -> SeedType {
        let data = [UInt8](publicKey.hexadecimal!)
        // FIXME: Is this correct?
        return data.count == 33 && data[0] == 0xED ? .ed25519 : .secp256k1
    }
    
    /// Validates a String is a valid XRP family seed.
    ///
    /// - Parameter seed: seed encoded using XRP alphabet
    /// - Returns: true if valid
    ///
    public static func validate(seed: String) -> Bool {
        do {
            if let _ = try SeedWallet.decodeSeed(seed: seed) {
                return true
            }
            return false
        } catch {
            return false
        }
    }
    public static func decode(seed: String) throws -> [UInt8]? {
        do {
            if let data = try SeedWallet.decodeSeed(seed: seed) {
                return data
            }
            return nil
        } catch {
            return nil
        }
    }
    
    public static func encode(bytes: [UInt8]) throws -> String? {
        do {
            let entropy = Entropy(bytes: bytes)
            return try SeedWallet.encodeSeed(entropy: entropy, type: .secp256k1)
        } catch {
            return nil
        }
    }
    
    public func sign(message: [UInt8]) -> [UInt8] {
        do {
            let algorithm = SeedWallet.getSeedTypeFrom(publicKey: self.publicKey).algorithm
            let signature = try algorithm.sign(message: message, privateKey: [UInt8](Data(hex: self.privateKey)))
    
            // verify signature
            let verified = try algorithm.verify(
                signature: signature,
                message: message,
                publicKey: [UInt8](Data(hex: self.publicKey))
            )
            if !verified {
                fatalError()
            }
    
            return signature
        } catch {
            print(error.localizedDescription)
            return []
        }
    }
    
    public static func verify(signature: [UInt8], message: [UInt8], publicKey: String) -> Bool {
        do {
            let algorithm = SeedWallet.getSeedTypeFrom(publicKey: publicKey).algorithm
            return try algorithm.verify(
                signature: signature,
                message: message,
                publicKey: [UInt8](Data(hex: publicKey))
            )
        } catch {
            print(error.localizedDescription)
            return false
        }
    }
    
    public func encodeClaim(dict: [String: Any]) throws -> [UInt8] {
        
        guard let channel = dict["channel"] as? String else {
            fatalError()
        }
        
        guard let amount = dict["amount"] as? Amount else {
            fatalError()
        }
        
        // add the prefix to the channel and amount
        let data: [UInt8] = HASH_CHANNEL_SIGN + [UInt8](channel.hexadecimal!) + [UInt8](UInt64(amount.drops).bigEndian.data)
        
        return data
    }
}
