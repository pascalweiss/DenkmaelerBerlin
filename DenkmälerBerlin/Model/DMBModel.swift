//
//  DMBModel.swift
//  DenkmälerBerlin
//
//  Created by Pascal Weiß on 18.11.15.
//  Copyright © 2015 HTWBerlin. All rights reserved.
//

import Foundation
import SQLite
import MapKit

/// Diese Klasse implementiert das Singleton-Pattern, wodruch sie nicht vom Entwickler selbst instanziiert werden muss.
/// Zugriff auf die Methoden werden - wie z.B, bei "NSUserDefaults.standardUserDefaults" - durch das statische Objekt "DMBModel.sharedInstance" gewährt.
/// Es liefert einige Methoden, mit denen Daten aus der Datenbank abgefragt werden können.
/// Z.B. können bestimmte Denkmäler anhand eines Suchstrings gesucht werden. 
/// Sämtliche Suchergebnisse sind Objekte, deren Klassen von "DMBEntity" erben. 
/// Diese haben die Fähigkeit, weitere Anfragen an die Datenbank zu stellen, wobei dann wiederum Objekte vom Typ DMBEntity zurück gegeben werden.
/// z.B. liefert ein Objekt der Klasse "DMBMonument" mit "getAddress" sämtliche Ortsdaten (Straße, Hausnummer, Longitude, Latitude) in Form eines DMBLocation-Objekts.
/// Dieses Verfahren ermöglicht einen möglichst komfortablen und effizenten Umgang mit der darunter liegenden Datenbank,
/// da sämtliche Operationen durch Methoden gekapselt werden, und gleichzeitig die benötigten Daten erst dann abgefragt werden, wenn sie benötigt werden.
/// Das Verfahren ist dem Apple eigenen Framework CoreData nachempfunden.
class DMBModel {
    
    static let sharedInstance = DMBModel()
    private let dbConnection: Connection
    private var filter: DMBFilter?
    private let debug = true

    private init() {
        print(NSBundle.mainBundle().pathForResource("DMBsqlite_v6", ofType: "db"))
        self.dbConnection = try! Connection(NSBundle.mainBundle().pathForResource("DMBsqlite_v6", ofType: "db")!, readonly: false)
    }
    
    func setFilter(filter:DMBFilter) {
        self.filter=filter
    }
    
    /*
     _____       _   _ _            ___                  _
    | ____|_ __ | |_(_) |_ _   _   / _ \ _   _  ___ _ __(_) ___  ___
    |  _| | '_ \| __| | __| | | | | | | | | | |/ _ \ '__| |/ _ \/ __|
    | |___| | | | |_| | |_| |_| | | |_| | |_| |  __/ |  | |  __/\__ \
    |_____|_| |_|\__|_|\__|\__, |  \__\_\\__,_|\___|_|  |_|\___||___/
                           |___/
    */
    
    func getAllParticipants()->[DMBParticipant]{
        return []
    }
    
    func getAllEpoches()->[DMBEpoche] {
        assert(false, "getAllMonuments() not implemented yet. I will do if required")
        return []
    }
    
    /// Liefert sämtliche Bezirke, die in der Datenbank vermerkt sind.
    /// Z.B. "Prenzlauer Berg", "Neukölln", etc. 
    /// Der Rückgabewert ist ein Array vom Typ DMBDistrict
    func getAllDistricts()->[DMBDistrict] {
        let districts = Table(DMBTable.district)
        return dbConnection.prepare(districts).map{row -> DMBDistrict in
            return DMBConverter.rowToDistrict(row, connection: dbConnection)
        }
    }
    
    func getAllSubDistricts()->[DMBSubDistrict] {
        assert(false, "getAllMonuments() not implemented yet. I will do if required")
        return []
    }
    
    func getAllRoutes()->[DMBRoute] {
        assert(false, "getAllMonuments() not implemented yet. I will do if required")
        return []
    }
    /// Liefert sämtliche Denkmaltypen. 
    /// Z.B.: "Baudenkmal" oder "Ensemble".
    /// Rückgabewert ist ein Array vom Typ DMBType.
    func getAllTypes()->[DMBType] {
        let types = Table(DMBTable.type)
        return dbConnection.prepare(types).map{row -> DMBType in
            return DMBConverter.rowToType(row, connection: dbConnection)
        }
    }
    
    /// Liefert sämtliche Denkmäler.
    /// Rückgabewert ist ein Array vom Typ DMBMonument.
    func getAllMonuments() -> [DMBMonument] {
        let monuments = Table(DMBTable.monument)
        return dbConnection.prepare(monuments)
            .map({row -> DMBMonument in
                return DMBConverter.rowToMonument(row, connection: dbConnection)
        })
    }
    
    /// Liefert sämtliche Denkmäler, die sich innerhalb der als Parameter übergebenen MKCooridnateRegion befinden.
    func getMonuments(area:MKCoordinateRegion) -> [DMBMonument]{
        let monuments  = Table(DMBTable.monument)
        let addresses  = Table(DMBTable.address)
        let addressRel = Table(DMBTable.addressRel)
        let inLongitude = area.center.longitude - area.span.longitudeDelta < DMBLocation.Expressions.long
            && DMBLocation.Expressions.long < area.center.longitude + area.span.longitudeDelta
        let inLatitude  = area.center.latitude - area.span.latitudeDelta < DMBLocation.Expressions.lat
            && DMBLocation.Expressions.lat < area.center.latitude + area.span.latitudeDelta
        return dbConnection.prepare(monuments
            .join(addressRel, on: monuments[DMBMonument.Expressions.id] == addressRel[DMBLocationRelation.Expressions.monumentId])
            .join(addresses, on: addressRel[DMBLocationRelation.Expressions.addressId] == addresses[DMBLocation.Expressions.id])
            .filter(inLongitude && inLatitude))
            .map({row -> DMBMonument in
                return DMBConverter.rowToMonument(row, connection: dbConnection)
        })
    }
    
    func searchMonuments(searchString: String) -> [String:[(Double,DMBMonument)]] {
        let tokens = createTokens(searchString)
        let m1 = rankedMonumentsByName(tokens)
        let m2 = rankedMonumentsByLocation(tokens)
        let m3 = rankedMonumentsByParticipant(tokens)
        return ["byName": m1, "byLocation": m2, "byParticipant": m3]
    }
    
/*
     ____            _               ___                  _
    / ___|  ___ __ _| | __ _ _ __   / _ \ _   _  ___ _ __(_) ___  ___
    \___ \ / __/ _` | |/ _` | '__| | | | | | | |/ _ \ '__| |/ _ \/ __|
     ___) | (_| (_| | | (_| | |    | |_| | |_| |  __/ |  | |  __/\__ \
    |____/ \___\__,_|_|\__,_|_|     \__\_\\__,_|\___|_|  |_|\___||___/
*/
    
    /// Gibt das kleinste Datum zurück
    func getMinDate() -> NSDate? {
        let datings = DMBTable.dating
        let from = DMBTimePeriod.Expressions.from.template
        let to   = DMBTimePeriod.Expressions.to.template
        let stmtFrom = dbConnection.prepare("SELECT min(\(from)) FROM \(datings)")
        let stmtTo   = dbConnection.prepare("SELECT min(\(to)) FROM \(datings)")
        let maxFrom = DMBConverter.stringToDate(stmtFrom.scalar() as! String)
        let maxTo   = DMBConverter.stringToDate(stmtTo.scalar() as! String)
        if maxTo != nil && maxFrom != nil {
            return {maxTo!.timeIntervalSinceDate(maxFrom!) > 0 ? maxFrom:maxTo}()
        }
        else if maxTo != nil {
            return maxTo
        }
        else if maxFrom != nil {
            return maxFrom
        }
        return nil
    }
    
    /// Gibt größte Datum zurück
    func getMaxDate() -> NSDate? {
        let datings = DMBTable.dating
        let from = DMBTimePeriod.Expressions.from.template
        let to   = DMBTimePeriod.Expressions.to.template
        let stmtFrom = dbConnection.prepare("SELECT max(\(from)) FROM \(datings)")
        let stmtTo   = dbConnection.prepare("SELECT max(\(to)) FROM \(datings)")
        let maxFrom = DMBConverter.stringToDate(stmtFrom.scalar() as! String)
        let maxTo   = DMBConverter.stringToDate(stmtTo.scalar() as! String)
        if maxTo != nil && maxFrom != nil {
            return {maxTo!.timeIntervalSinceDate(maxFrom!) > 0 ? maxTo:maxFrom}()
        }
        else if maxTo != nil {
            return maxTo
        }
        else if maxFrom != nil {
            return maxFrom
        }
        return nil
    }
    
/*
                             _             _
     ___  ___  __ _ _ __ ___| |__     __ _| | __ _  ___
    / __|/ _ \/ _` | '__/ __| '_ \   / _` | |/ _` |/ _ \
    \__ \  __/ (_| | | | (__| | | | | (_| | | (_| | (_) |
    |___/\___|\__,_|_|  \___|_| |_|  \__,_|_|\__, |\___/
                                             |___/
*/
    /// Eine Methode, mit der Denkmäler anhand ihres Namens gesucht werden.
    /// Als Übergabeparameter kann ein String übergeben werden.
    /// Dieser kann mehrere Wörter beinhalten, wobei die Denkmäler anhand jedes einzelnen Wortes gesucht werden.
    private func searchMonumentsByName(token: String) -> [(Double,DMBMonument)] {
        let monuments = Table(DMBTable.monument)
        return dbConnection.prepare(monuments
            .filter(monuments[DMBMonument.Expressions.name].lowercaseString.like(searchableString(token))))
            .map({row -> (Double,DMBMonument) in
                let monum = DMBConverter.rowToMonument(row, connection: dbConnection)
                let match = getMatch(monum.getName()!, searchString: token)
                return (match,monum)
            })
        //            .sort({$0.0 > $1.0})
    }
    
    private func searchMonumentsByLocation(token: String) -> [(Double,DMBMonument)] {
        let monuments   = Table(DMBTable.monument)
        let locationRel = Table(DMBTable.addressRel)
        let locations   = Table(DMBTable.address)
        return dbConnection.prepare(monuments
            .join(locationRel, on: monuments[DMBMonument.Expressions.id] == locationRel[DMBLocationRelation.Expressions.monumentId])
            .join(locations, on: locationRel[DMBLocationRelation.Expressions.addressId] == locations[DMBLocation.Expressions.id])
            .filter(locations[DMBLocation.Expressions.street].lowercaseString.like(searchableString(token))))
            .map({row -> (Double, DMBMonument) in
                let address = row.get(DMBLocation.Expressions.street)
                let monum   = DMBConverter.rowToMonument(row, connection: dbConnection, table: monuments)
                let match   = getMatch(address!, searchString: token)
                return (match, monum)
            })
    }
    
    private func searchMonumentsByParticipant(token: String) -> [(Double, DMBMonument)] {
        let monuments = Table(DMBTable.monument)
        let participantsRel = Table(DMBTable.participantRel)
        let participants = Table(DMBTable.participant)
        //TODO
        return []
    }
    
    private func searchableString(string: String) -> String {
        return "%" + string + "%"
    }
    
    private func createTokens(s: String) -> [String] {
        let words = s.characters.split{$0 == " "}.map(String.init)   //TODO Bisher bloss split bei "_"
        return Array(Set(words.map{$0.lowercaseString}))
    }
    
    private func getMatch(resultString: String, searchString: String) -> Double {
        let mismatch = resultString.lowercaseString.stringByReplacingOccurrencesOfString(searchString, withString: "")
        let match = 1-Double(mismatch.characters.count) / Double(resultString.characters.count)
        return match
    }
    
    private func rankMonuments(monuments:[(Double,DMBMonument)]) -> [(Double, DMBMonument)]{
        return monuments.groupBy({$0.1.getName()!}).map({groupedMon -> (Double,DMBMonument) in
            let m:DMBMonument = groupedMon.1[0].1
            return groupedMon.1.reduce((0,m), combine: {
                (m1,m2) -> (Double, DMBMonument) in
                return (m1.0 + m2.0, m)
            })
        }).sort({$0.0 > $1.0})
    }
    
    private func rankedMonumentsByName(tokens: [String]) -> [(Double,DMBMonument)] {
        return rankMonuments(tokens.flatMap({word -> [(Double,DMBMonument)] in
            return self.searchMonumentsByName(word)
        }))
    }
    
    private func rankedMonumentsByLocation(tokens: [String]) -> [(Double,DMBMonument)] {
        return rankMonuments(tokens.flatMap({word -> [(Double,DMBMonument)] in
            return self.searchMonumentsByLocation(word)
        }))
    }
    
    private func rankedMonumentsByParticipant(tokens: [String]) -> [(Double, DMBMonument)] {
        return rankMonuments(tokens.flatMap({word -> [(Double, DMBMonument)] in
            return self.searchMonumentsByParticipant(word)
        }))
    }
}



