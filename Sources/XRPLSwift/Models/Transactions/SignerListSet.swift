//
//  SignerListSet.swift
//  AnyCodable
//
//  Created by Mitch Lang on 2/10/20.
//

import Foundation

public struct SignerEntry {
    var Account: String
    var SignerWeight: Int
}

public class SignerListSet: Transaction {
    
    public init(wallet: Wallet, signerQuorum: UInt32, signerEntries: [SignerEntry]) {
        
        let signers = signerEntries.map { (signerEntry) -> NSDictionary in
            return NSDictionary(dictionary: [
                "SignerEntry" : NSDictionary(dictionary: [
                    "Account" : signerEntry.Account,
                    "SignerWeight" : signerEntry.SignerWeight,
                ])
            ])
        }
            
        // dictionary containing partial transaction fields
        let _fields: [String:Any] = [
            "TransactionType": "SignerListSet",
            "SignerQuorum": signerQuorum,
            "SignerEntries": signers
        ]
    
        super.init(wallet: wallet, fields: _fields)
    }

}
