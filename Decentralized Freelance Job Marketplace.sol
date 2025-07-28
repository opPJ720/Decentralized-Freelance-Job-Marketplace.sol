// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Project {
    // State variables
    address public owner;
    uint256 public jobCounter;
    uint256 public platformFeePercentage = 5; // 5% platform fee
    
    // Enums
    enum JobStatus { Open, InProgress, Completed, Disputed, Cancelled }
    
    // Structs
    struct Job {
        uint256 id;
        address client;
        address freelancer;
        string title;
        string description;
        uint256 budget;
        uint256 deadline;
        JobStatus status;
        bool clientApproved;
        bool freelancerDelivered;
        uint256 createdAt;
    }
    
    struct Proposal {
        address freelancer;
        uint256 jobId;
        uint256 proposedBudget;
        string coverLetter;
        uint256 proposedDeadline;
        bool isAccepted;
    }
    
    // Mappings
    mapping(uint256 => Job) public jobs;
    mapping(uint256 => Proposal[]) public jobProposals;
    mapping(address => uint256[]) public clientJobs;
    mapping(address => uint256[]) public freelancerJobs;
    mapping(address => uint256) public userRatings;
    mapping(address => uint256) public userRatingCount;
    
    // Events
    event JobCreated(uint256 indexed jobId, address indexed client, string title, uint256 budget);
    event ProposalSubmitted(uint256 indexed jobId, address indexed freelancer, uint256 proposedBudget);
    event JobAssigned(uint256 indexed jobId, address indexed freelancer);
    event JobCompleted(uint256 indexed jobId, address indexed client, address indexed freelancer);
    event PaymentReleased(uint256 indexed jobId, uint256 amount, address indexed freelancer);
    event JobCancelled(uint256 indexed jobId, address indexed client);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner can call this function");
        _;
    }
    
    modifier onlyClient(uint256 _jobId) {
        require(msg.sender == jobs[_jobId].client, "Only job client can call this function");
        _;
    }
    
    modifier onlyFreelancer(uint256 _jobId) {
        require(msg.sender == jobs[_jobId].freelancer, "Only assigned freelancer can call this function");
        _;
    }
    
    modifier jobExists(uint256 _jobId) {
        require(_jobId > 0 && _jobId <= jobCounter, "Job does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        jobCounter = 0;
    }
    
    // Core Function 1: Create Job
    function createJob(
        string memory _title,
        string memory _description,
        uint256 _deadline
    ) external payable {
        require(msg.value > 0, "Job budget must be greater than 0");
        require(bytes(_title).length > 0, "Job title cannot be empty");
        require(_deadline > block.timestamp, "Deadline must be in the future");
        
        jobCounter++;
        
        jobs[jobCounter] = Job({
            id: jobCounter,
            client: msg.sender,
            freelancer: address(0),
            title: _title,
            description: _description,
            budget: msg.value,
            deadline: _deadline,
            status: JobStatus.Open,
            clientApproved: false,
            freelancerDelivered: false,
            createdAt: block.timestamp
        });
        
        clientJobs[msg.sender].push(jobCounter);
        
        emit JobCreated(jobCounter, msg.sender, _title, msg.value);
    }
    
    // Core Function 2: Submit Proposal and Assign Job
    function submitProposal(
        uint256 _jobId,
        uint256 _proposedBudget,
        string memory _coverLetter,
        uint256 _proposedDeadline
    ) external jobExists(_jobId) {
        require(jobs[_jobId].status == JobStatus.Open, "Job is not open for proposals");
        require(msg.sender != jobs[_jobId].client, "Client cannot submit proposal to own job");
        require(_proposedBudget > 0, "Proposed budget must be greater than 0");
        require(_proposedDeadline > block.timestamp, "Proposed deadline must be in the future");
        
        // Check if freelancer already submitted a proposal
        Proposal[] storage proposals = jobProposals[_jobId];
        for (uint i = 0; i < proposals.length; i++) {
            require(proposals[i].freelancer != msg.sender, "Proposal already submitted");
        }
        
        proposals.push(Proposal({
            freelancer: msg.sender,
            jobId: _jobId,
            proposedBudget: _proposedBudget,
            coverLetter: _coverLetter,
            proposedDeadline: _proposedDeadline,
            isAccepted: false
        }));
        
        emit ProposalSubmitted(_jobId, msg.sender, _proposedBudget);
    }
    
    function assignJob(uint256 _jobId, address _freelancer) 
        external 
        jobExists(_jobId) 
        onlyClient(_jobId) 
    {
        require(jobs[_jobId].status == JobStatus.Open, "Job is not open");
        
        // Verify freelancer submitted a proposal
        bool proposalExists = false;
        Proposal[] storage proposals = jobProposals[_jobId];
        for (uint i = 0; i < proposals.length; i++) {
            if (proposals[i].freelancer == _freelancer) {
                proposals[i].isAccepted = true;
                proposalExists = true;
                break;
            }
        }
        require(proposalExists, "Freelancer has not submitted a proposal");
        
        jobs[_jobId].freelancer = _freelancer;
        jobs[_jobId].status = JobStatus.InProgress;
        freelancerJobs[_freelancer].push(_jobId);
        
        emit JobAssigned(_jobId, _freelancer);
    }
    
    // Core Function 3: Complete Job and Release Payment
    function deliverWork(uint256 _jobId) 
        external 
        jobExists(_jobId) 
        onlyFreelancer(_jobId) 
    {
        require(jobs[_jobId].status == JobStatus.InProgress, "Job is not in progress");
        require(block.timestamp <= jobs[_jobId].deadline, "Job deadline has passed");
        
        jobs[_jobId].freelancerDelivered = true;
        
        // If client has already approved, complete the job
        if (jobs[_jobId].clientApproved) {
            _completeJob(_jobId);
        }
    }
    
    function approveWork(uint256 _jobId) 
        external 
        jobExists(_jobId) 
        onlyClient(_jobId) 
    {
        require(jobs[_jobId].status == JobStatus.InProgress, "Job is not in progress");
        
        jobs[_jobId].clientApproved = true;
        
        // If freelancer has already delivered, complete the job
        if (jobs[_jobId].freelancerDelivered) {
            _completeJob(_jobId);
        }
    }
    
    function _completeJob(uint256 _jobId) internal {
        jobs[_jobId].status = JobStatus.Completed;
        
        uint256 platformFee = (jobs[_jobId].budget * platformFeePercentage) / 100;
        uint256 freelancerPayment = jobs[_jobId].budget - platformFee;
        
        // Transfer payment to freelancer
        payable(jobs[_jobId].freelancer).transfer(freelancerPayment);
        
        // Transfer platform fee to owner
        payable(owner).transfer(platformFee);
        
        emit JobCompleted(_jobId, jobs[_jobId].client, jobs[_jobId].freelancer);
        emit PaymentReleased(_jobId, freelancerPayment, jobs[_jobId].freelancer);
    }
    
    // Additional utility functions
    function cancelJob(uint256 _jobId) 
        external 
        jobExists(_jobId) 
        onlyClient(_jobId) 
    {
        require(
            jobs[_jobId].status == JobStatus.Open || 
            jobs[_jobId].status == JobStatus.InProgress,
            "Job cannot be cancelled"
        );
        
        jobs[_jobId].status = JobStatus.Cancelled;
        
        // Refund the client
        payable(jobs[_jobId].client).transfer(jobs[_jobId].budget);
        
        emit JobCancelled(_jobId, msg.sender);
    }
    
    function getJobProposals(uint256 _jobId) 
        external 
        view 
        jobExists(_jobId) 
        returns (Proposal[] memory) 
    {
        return jobProposals[_jobId];
    }
    
    function getClientJobs(address _client) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return clientJobs[_client];
    }
    
    function getFreelancerJobs(address _freelancer) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return freelancerJobs[_freelancer];
    }
    
    function updatePlatformFee(uint256 _newFeePercentage) 
        external 
        onlyOwner 
    {
        require(_newFeePercentage <= 10, "Platform fee cannot exceed 10%");
        platformFeePercentage = _newFeePercentage;
    }
    
    // Emergency withdrawal function (only owner)
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
    
    // Get contract balance
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
