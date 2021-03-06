//
//  TrackListViewController.swift
//  Disco
//
//  Created by Tim on 8/25/16.
//  Copyright © 2016 Tim Chamberlin. All rights reserved.
//

import UIKit


let kTrackListDidLoad = "TrackListDidLoad"
let kUpNextListDidUpdate = "UpNextListDidUpdate"
let kTrackListDidRemoveSong = "TrackListDidUpdate"

let trackCellReuseIdentifier = "trackCell"
let nowPlayingCellReuseIdentifier = "nowPlayingCell"

class TrackListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, AddTrackToPlaylistDelegate, TrackTableViewCellDelegate {
    
    @IBOutlet weak var tableView: UITableView!
    
    var playlist: Playlist?
    var currentUser: User = UserController.sharedController.currentUser!
    
    var musicSearchController: UISearchController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.playlist?.upNext = []
        self.playlist?.nowPlaying = nil
        addTrackObservers(forPlaylistType: .Contributing)
        registerCustomCells()
        if let playlist = playlist {
            self.title = playlist.name
        }
    }
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(true)
        setupViewForEmptyQueue()
    }
    
    deinit {
        if let queue = playlist {
            PlaylistController.sharedController.removeNowPlayingObserverFromQueue(playlist!)
            PlaylistController.sharedController.removeUpNextObserverFromQueue(playlist!)
            for track in queue.upNext {
                TrackController.removeVoteListenerFromTrack(track, inQueue: queue)
            }
        }
    }
    
    func registerCustomCells() {
        tableView.registerNib(UINib(nibName: "TrackTableViewCell", bundle: nil), forCellReuseIdentifier: trackCellReuseIdentifier)
        tableView.registerNib(UINib(nibName: "NowPlayingTableViewCell", bundle: nil), forCellReuseIdentifier: nowPlayingCellReuseIdentifier)
    }
    
    
    func addTrackObservers(forPlaylistType playlistType: PlaylistType) {
        // Observers added:
        // addUpNextObserverToQueue
        // attachVoteListener
        // addNowPlayingObserver
        
        guard let queue = playlist, currentUser = UserController.sharedController.currentUser else { return }
        PlaylistController.sharedController.addUpNextObserverToQueue(queue) { [weak self] (track, didAdd) in
            if let track = track {
                if didAdd {
                    queue.upNext.append(track)
                    self?.updateTableViewWithQueueData()
                    
                    // Add vote observers
                    TrackController.getVoteStatusForTrackWithID(track.firebaseUID, inPlaylistWithID: queue.uid, ofType: playlistType, user: currentUser, completion: { [weak self] (voteStatus, success) in
                        if success {
                            track.currentUserVoteStatus = voteStatus
                            self?.updateTableViewWithQueueData()
                        }
                    })
                    TrackController.attachVoteListener(forTrack: track, inPlaylist: queue, completion: { [weak self] (newVoteCount, success) in
                        track.voteCount = newVoteCount
                        self?.updateTableViewWithQueueData()
                    })
                } else { // Track removed
                    queue.upNext = queue.upNext.filter { $0 != track }
                    self?.updateTableViewWithQueueData()
                }
            }
        }
        // Add nowPlaying observer
        PlaylistController.sharedController.addNowPlayingObserverToQueue(queue, completion: { [weak self] (track, didAdd) in
            guard let track = track else { return }
            if didAdd {
                queue.nowPlaying = track
                self?.updateTableViewWithQueueData()
            } else {
                queue.nowPlaying = nil
                self?.updateTableViewWithQueueData()
            }
        })
    }
    
    func updateTableViewWithQueueData() {
        guard let queue = playlist else { return }
        queue.upNext = TrackController.sortTracklistByVoteCount(queue.upNext)
        tableView.reloadData()
        setupViewForEmptyQueue()
    }
    
    func setupViewForEmptyQueue() {
        guard let queue = playlist else {
            tableView.hidden = true
            return
        }
        if queue.upNext.isEmpty && queue.nowPlaying == nil { // If no songs
            tableView.hidden = true
            
        } else {
            tableView.hidden = false
        }
    }
    
    // MARK: - UITableViewDataSource
    
    func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return 2
    }
    
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let playlist = playlist else { return 0 }
        if section == 0 {
            return playlist.nowPlaying != nil ? 1 : 0
        } else if section == 1 {
            return playlist.upNext.count
        }
        return 0
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            if let cell = tableView.dequeueReusableCellWithIdentifier(nowPlayingCellReuseIdentifier, forIndexPath: indexPath) as? NowPlayingTableViewCell, playlist = playlist, nowPlaying = playlist.nowPlaying {
                let track = nowPlaying
                cell.updateCellWithTrack(track)
                return cell
            }
        } else if indexPath.section == 1 {
            if let cell = tableView.dequeueReusableCellWithIdentifier(trackCellReuseIdentifier, forIndexPath: indexPath) as? TrackTableViewCell, playlist = playlist {
                if !playlist.upNext.isEmpty {
                    let track = playlist.upNext[indexPath.row]
                    cell.track = track
                    cell.voteStatus = track.currentUserVoteStatus
                    cell.updateCellWithTrack(track)
                    cell.delegate = self
                    return cell
                }
            }
        }
        return UITableViewCell()
    }
    
    func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        if indexPath.section == 0 {
            return nowPlayingTableViewCellHeight
        } else {
            return trackTableViewCellHeight
        }
    }
    
    func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 {
            return "Now Playing"
        } else if section == 1 {
            return "Up Next"
        } else {
            return ""
        }
    }
    
    // MARK: - TrackTableViewCellDelegate Method
    
    func didPressVoteButton(sender: TrackTableViewCell, voteType: VoteType) {
        guard let currentUser = UserController.sharedController.currentUser, playlist = playlist, track = sender.track else { return }
        
        TrackController.user(currentUser, didVoteWithType: voteType, withVoteStatus: (sender.track?.currentUserVoteStatus)!, onTrack: track, inPlaylist: playlist, ofPlaylistType: .Contributing) { (success) in
            //
        }
    }    
    
    // MARK: - AddTrackToPlaylistDelegate Method
    
    func willAddTrackToPlaylist(track: Track) {
        musicSearchController?.active = false
        musicSearchController?.searchBar.text = ""
        guard let playlistID = playlist?.uid else { return }
        track.playlistID = playlistID
        PlaylistController.sharedController.addTrack(track, toQueue: self.playlist!) { (success) in
            // Fetch playlist tracks and reload tableView
            if success {
                print("Update playlist with track: \(track.name)")
                ProgressHUD.showSuccess("Track added")
            } else {
                ProgressHUD.showError("Error adding track to queue")
            }
            
        }
    }
    
    // MARK: - Navigation
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "addTrackToPlaylistSegue" {
            let navVC = segue.destinationViewController as? UINavigationController
            guard let searchVC = navVC?.viewControllers.first as? MusicSearchTableViewController else { return }
            searchVC.delegate = self
        }
    }
    
    // MARK: - IBActions
    
    @IBAction func addFirstSongToQueueTapped(sender: AnyObject) {
        self.performSegueWithIdentifier("addTrackToPlaylistSegue", sender: self)
    }
}