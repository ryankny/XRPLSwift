//
//  Ledger.swift
//  XRPLSwift
//
//  Created by Mitch Lang on 5/10/19.
//

import Foundation
import NIO

enum LedgerError: Error {
    case runtimeError(String)
}

public class Ledger: NSObject {
    
    // WebSocket is always available through SPM
    // WebSocket is only available through CocoaPods on newer OS
#if canImport(WebSocketKit)
    public static var ws: XRPLWebSocket = LinuxWebSocket()
#elseif !os(Linux)
    @available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
    public static var ws: XRPLWebSocket = AppleWebSocket()
#endif
    
    // JSON-RPC
    public var url: URL = .xrpl_rpc_MainNetS1
    
    required public convenience override init() {
        self.init(endpoint: .xrpl_rpc_MainNetS1)
    }
    
    public init(endpoint: URL) {
        self.url = endpoint
    }
    
    public func getTxs(account: String) -> EventLoopFuture<[HistoricalTransaction]> {
        
        let promise = eventGroup.next().makePromise(of: [HistoricalTransaction].self)
        
        let parameters: [String: Any] = [
            "method" : "account_tx",
            "params": [
                [
                    "account" : account,
                    "ledger_index_min" : -1,
                    "ledger_index_max" : -1,
                ]
            ]
        ]
        
        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
            let JSON = result as! NSDictionary
            let info = JSON["result"] as! NSDictionary
            let status = info["status"] as! String
            if status != "error" {
                let _array = info["transactions"] as! [NSDictionary]
                let filtered = _array.filter({ (dict) -> Bool in
                    // validated is optional and isn't always included in the response JSOn
                    let validated = dict["validated"] as? Bool
                    let tx = dict["tx"] as! NSDictionary
                    let meta = dict["meta"] as! NSDictionary
                    let res = meta["TransactionResult"] as! String
                    let type = tx["TransactionType"] as! String
                    return (validated ?? true) && type == "Payment" && res == "tesSUCCESS"
                })
                
                let transactions = filtered.map({ (dict) -> HistoricalTransaction in
                    let tx = dict["tx"] as! NSDictionary
                    let destination = tx["Destination"] as! String
                    let source = tx["Account"] as! String
                    let amount = tx["Amount"] as! String
                    let timestamp = tx["date"] as! Int
                    let date = Date(timeIntervalSince1970: 946684800+Double(timestamp))
                    let type = account == source ? "Sent" : "Received"
                    let address = account == source ? destination : source
                    return HistoricalTransaction(type: type, address: address, amount: try! Amount(drops: Int(amount)!), date: date, raw: tx)
                })
                promise.succeed(transactions.sorted(by: { (lh, rh) -> Bool in
                    lh.date > rh.date
                }))
            } else {
                let errorMessage = info["error_message"] as! String
                let error = LedgerError.runtimeError(errorMessage)
                promise.fail(error)
            }
        }.recover { (error) in
            promise.fail(error)
        }
        
        return promise.futureResult
        
    }
    
    public func getBalance(address: String) -> EventLoopFuture<Amount> {
        
        let promise = eventGroup.next().makePromise(of: Amount.self)
        
        let parameters: [String: Any] = [
            "method" : "account_info",
            "params": [
                [
                    "account" : address
                ]
            ]
        ]
        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
            let JSON = result as! NSDictionary
            let info = JSON["result"] as! NSDictionary
            let status = info["status"] as! String
            if status != "error" {
                let account = info["account_data"] as! NSDictionary
                let balance = account["Balance"] as! String
                let amount = try! Amount(drops: Int(balance)!)
                promise.succeed( amount)
            } else {
                let errorMessage = info["error_message"] as! String
                let error = LedgerError.runtimeError(errorMessage)
                promise.fail(error)
            }
        }.recover { (error) in
            promise.fail(error)
        }
        
        return promise.futureResult
    }
    
    public func getAccountInfo(account: String) -> EventLoopFuture<AccountInfo> {
        let promise = eventGroup.next().makePromise(of: AccountInfo.self)
        let parameters: [String: Any] = [
            "method" : "account_info",
            "params": [
                [
                    "account" : account,
                    "strict": true,
                    "ledger_index": "current",
                    "queue": true
                ]
            ]
        ]
        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
            let JSON = result as! NSDictionary
            let info = JSON["result"] as! NSDictionary
            let status = info["status"] as! String
            if status != "error" {
                let account = info["account_data"] as! NSDictionary
                let balance = account["Balance"] as! String
                let address = account["Account"] as! String
                let sequence = account["Sequence"] as! Int
                let accountInfo = AccountInfo(address: address, drops: Int(balance)!, sequence: sequence)
                promise.succeed( accountInfo)
            } else {
                let errorMessage = info["error_message"] as! String
                let error = LedgerError.runtimeError(errorMessage)
                promise.fail(error)
            }
        }.recover { (error) in
            promise.fail(error)
        }
        return promise.futureResult
    }
    
    public func getSignerList(address: String) -> EventLoopFuture<NSDictionary> {
        
        let promise = eventGroup.next().makePromise(of: NSDictionary.self)
        
        let parameters: [String: Any] = [
            "method" : "account_objects",
            "params": [
                [
                    "account" : address,
                    "ledger_index": "validated",
                    "type": "signer_list",
                ]
            ]
        ]
        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
            let JSON = result as! NSDictionary
            let info = JSON["result"] as! NSDictionary
            let status = info["status"] as! String
            if status != "error" {
                promise.succeed( info)
            } else {
                let errorMessage = info["error_message"] as! String
                let error = LedgerError.runtimeError(errorMessage)
                promise.fail(error)
            }
        }.recover { (error) in
            promise.fail(error)
        }
        
        return promise.futureResult
        
    }
    
    public func getPendingEscrows(address: String) -> EventLoopFuture<NSDictionary> {
        
        let promise = eventGroup.next().makePromise(of: NSDictionary.self)
        
        let parameters: [String: Any] = [
            "method" : "account_objects",
            "params": [
                [
                    "account" : address,
                    "ledger_index": "validated",
                    "type": "escrow",
                ]
            ]
        ]
        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
            let JSON = result as! NSDictionary
            let info = JSON["result"] as! NSDictionary
            let status = info["status"] as! String
            if status != "error" {
                promise.succeed( info)
            } else {
                let errorMessage = info["error_message"] as! String
                let error = LedgerError.runtimeError(errorMessage)
                promise.fail(error)
            }
        }.recover { (error) in
            promise.fail(error)
        }
        
        return promise.futureResult
        
    }
    
    public func getTrustLines(address: String, symbol: String, issuer: String) -> EventLoopFuture<Currency> {
        
        let promise = eventGroup.next().makePromise(of: Currency.self)
        
        let parameters: [String: Any] = [
            "method" : "account_lines",
            "params": [
                [
                    "account" : address,
                ]
            ]
        ]
        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
            let JSON = result as! NSDictionary
            let info = JSON["result"] as! NSDictionary
            let status = info["status"] as! String
            if status != "error" {
                let lines = info["lines"] as! [[String: AnyObject]]
                for line in lines {
                    let currency = line["currency"] as! String
                    let account = line["account"] as! String
                    if symbol == currency && account == issuer {
                        let address = line["account"] as! String
                        let balance = line["balance"] as! String
                        let limit = line["limit"] as! String
                        let currencyInfo = Currency(
                            address: address,
                            balance: balance,
                            currency: currency,
                            limit: limit
                        )
                        promise.succeed(currencyInfo)
                    }
                }
                let error = LedgerError.runtimeError("No Currency Found")
                promise.fail(error)
            } else {
                let errorMessage = info["error_message"] as! String
                let error = LedgerError.runtimeError(errorMessage)
                promise.fail(error)
            }
        }.recover { (error) in
            promise.fail(error)
        }
        
        return promise.futureResult
        
    }
    
//    public static func getAccountChannels(account: String, address: String) -> EventLoopFuture<NSDictionary> {
//
//        let promise = eventGroup.next().makePromise(of: NSDictionary.self)
//
//        let parameters: [String: Any] = [
//            "method" : "account_channels",
//            "params": [
//                [
//                    "account" : account,
//                    "destination_account": address,
//                    "ledger_index": "validated",
//                ]
//            ]
//        ]
//        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
//            let JSON = result as! NSDictionary
//            let info = JSON["result"] as! NSDictionary
//            let status = info["status"] as! String
//            if status != "error" {
//                promise.succeed(info)
//            } else {
//                let errorMessage = info["error_message"] as! String
//                let error = LedgerError.runtimeError(errorMessage)
//                promise.fail(error)
//            }
//        }.recover { (error) in
//            promise.fail(error)
//        }
//
//        return promise.futureResult
//
//    }
    
    public func currentLedgerInfo() -> EventLoopFuture<CurrentLedgerInfo> {
        let promise = eventGroup.next().makePromise(of: CurrentLedgerInfo.self)
        let parameters: [String: Any] = [
            "method" : "fee"
        ]
        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
            let JSON = result as! NSDictionary
            let info = JSON["result"] as! NSDictionary
            let drops = info["drops"] as! NSDictionary
            let min = drops["minimum_fee"] as! String
            let max = drops["median_fee"] as! String
            let ledger = info["ledger_current_index"] as! Int
            let ledgerInfo = CurrentLedgerInfo(index: ledger, minFee: Int(min)!, maxFee: Int(max)!)
            promise.succeed( ledgerInfo)
        }.recover { (error) in
            promise.fail(error)
        }
        return promise.futureResult
    }
    
    public func submit(txBlob: String) -> EventLoopFuture<NSDictionary> {
        let promise = eventGroup.next().makePromise(of: NSDictionary.self)
        let parameters: [String: Any] = [
            "method" : "submit",
            "params": [
                [
                    "tx_blob": txBlob
                ]
            ]
        ]
        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
            let JSON = result as! NSDictionary
            let info = JSON["result"] as! NSDictionary
            promise.succeed( info)
        }.recover { (error) in
            promise.fail(error)
        }
        return promise.futureResult
    }
    
//    public static func authorizeChannelClaim(channel: String, secret: String, amount: Int) -> EventLoopFuture<NSDictionary> {
//
//        let promise = eventGroup.next().makePromise(of: NSDictionary.self)
//
//        let parameters: [String: Any] = [
//            "method" : "channel_authorize",
//            "params": [
//                [
//                    "channel_id" : channel,
//                    "secret": secret,
//                    "amount": String(amount),
//                ]
//            ]
//        ]
//        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
//            let JSON = result as! NSDictionary
//            let info = JSON["result"] as! NSDictionary
//            let status = info["status"] as! String
//            if status != "error" {
//                promise.succeed(info)
//            } else {
//                let errorMessage = info["error_message"] as! String
//                let error = LedgerError.runtimeError(errorMessage)
//                promise.fail(error)
//            }
//        }.recover { (error) in
//            promise.fail(error)
//        }
//        return promise.futureResult
//    }
    
//    public static func verifyChannelClaim(channel: String, signature: String, amount: Int, publicKey: String) -> EventLoopFuture<NSDictionary> {
//
//        let promise = eventGroup.next().makePromise(of: NSDictionary.self)
//
//        let parameters: [String: Any] = [
//            "method" : "channel_verify",
//            "params": [
//                [
//                    "channel_id" : channel,
//                    "signature": signature,
//                    "amount": String(amount),
//                    "public_key": publicKey
//                ]
//            ]
//        ]
//        _ = HTTP.post(url: url, parameters: parameters).map { (result) in
//            let JSON = result as! NSDictionary
//            let info = JSON["result"] as! NSDictionary
//            let status = info["status"] as! String
//            if status != "error" {
//                promise.succeed(info)
//            } else {
//                let errorMessage = info["error_message"] as! String
//                let error = LedgerError.runtimeError(errorMessage)
//                promise.fail(error)
//            }
//        }.recover { (error) in
//            promise.fail(error)
//        }
//        return promise.futureResult
//    }
    
}
