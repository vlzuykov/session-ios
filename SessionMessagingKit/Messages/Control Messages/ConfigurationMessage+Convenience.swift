
extension ConfigurationMessage {

    public static func getCurrent() -> ConfigurationMessage? {
        let storage = Storage.shared
        guard let user = storage.getUser() else { return nil }
        
        let displayName = user.name
        let profilePictureURL = user.profilePictureURL
        let profileKey = user.profileEncryptionKey?.keyData
        var closedGroups: Set<ClosedGroup> = []
        var openGroups: Set<String> = []
        var contacts: Set<Contact> = []
        var contactCount = 0
        
        Storage.read { transaction in
            TSGroupThread.enumerateCollectionObjects(with: transaction) { object, _ in
                guard let thread = object as? TSGroupThread else { return }
                
                switch thread.groupModel.groupType {
                    case .closedGroup:
                        guard thread.isCurrentUserMemberInGroup() else { return }
                        
                        let groupID = thread.groupModel.groupId
                        let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupID)
                        
                        guard storage.isClosedGroup(groupPublicKey), let encryptionKeyPair = storage.getLatestClosedGroupEncryptionKeyPair(for: groupPublicKey) else {
                            return
                        }
                        
                        let closedGroup = ClosedGroup(
                            publicKey: groupPublicKey,
                            name: thread.groupModel.groupName!,
                            encryptionKeyPair: encryptionKeyPair,
                            members: Set(thread.groupModel.groupMemberIds),
                            admins: Set(thread.groupModel.groupAdminIds),
                            expirationTimer: thread.disappearingMessagesDuration(with: transaction)
                        )
                        closedGroups.insert(closedGroup)
                        
                    case .openGroup:
                        if let openGroup = storage.getOpenGroup(for: thread.uniqueId!) {
                            openGroups.insert("\(openGroup.server)/\(openGroup.room)?public_key=\(openGroup.publicKey)")
                        }
                        
                    default: break
                }
            }
            
            var truncatedContacts = storage.getAllContacts()
            
            if truncatedContacts.count > 200 {
                truncatedContacts = Set(Array(truncatedContacts)[0..<200])
            }
            
            truncatedContacts.forEach { contact in
                let publicKey = contact.sessionID
                let threadID = TSContactThread.threadID(fromContactSessionID: publicKey)
                
                guard
                    let thread = TSContactThread.fetch(uniqueId: threadID, transaction: transaction),
                    thread.shouldBeVisible &&
                    !SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(publicKey)
                else {
                    return
                }
                
                let profilePictureURL = contact.profilePictureURL
                let profileKey = contact.profileEncryptionKey?.keyData
                let contact = ConfigurationMessage.Contact(
                    publicKey: publicKey,
                    displayName: (contact.name ?? publicKey),
                    profilePictureURL: profilePictureURL,
                    profileKey: profileKey,
                    isApproved: contact.isApproved,
                    isBlocked: contact.isBlocked,
                    didApproveMe: contact.didApproveMe
                )
                
                contacts.insert(contact)
                contactCount += 1
            }
        }
        
        return ConfigurationMessage(
            displayName: displayName,
            profilePictureURL: profilePictureURL,
            profileKey: profileKey,
            closedGroups: closedGroups,
            openGroups: openGroups,
            contacts: contacts
        )
    }
}
