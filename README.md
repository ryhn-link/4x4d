# 4x4d
Matrix (the chat protocol) Client-Server bot library.  
API for a limited subset of the Matrix protocol intended in use for bots.  
This library doesn't have any support for commands out of the box, you need to implement that yourself.  

## Supported features
- [x] Password login  
- [x] List joined rooms  
- [x] Sync  
	- [x] Receiving invites  
	- [X] Receiving messages (Text messages only for now)
- [ ] Filters  
- [x] Joining rooms  
- [x] Mark messages as read  
- [x] Send message  
- [x] Resolve room aliases
- [x] Uploading files
- [x] Send images (Note: on Element Web they fail to load, the img src URL gives 404)
- [x] Device info
- [x] Presence
- [x] Storing and getting config data
- [x] Message reactions (Why is this not in the spec?)
- [ ] Creating rooms
- [ ] Direct messages
- [ ] E2E encryption???  

## License
This project is licensed under the [GNU Lesser General Public License](https://www.gnu.org/licenses/lgpl-3.0.en.html).  
This project may use parts of [dotty](https://github.com/rinfz/dotty)