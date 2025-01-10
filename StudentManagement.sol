// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract StudentManagement {
    struct Student {
        uint256 id;
        string studentId;
        string fullName;
        string dateOfBirth;
        string gender;
        string major;
        string hometown;
        string permanentAddress;
    }

    Student[] private students;
    mapping(uint256 => uint256) private studentIndexById;
    mapping(string => bool) private studentExistsByStudentId;

    uint256 private studentCount = 0;
    address private owner;

    event StudentAdded(uint256 id, string studentId, string fullName);
    event StudentUpdated(uint256 id, string studentId, string fullName);
    event StudentDeleted(uint256 id, string studentId);
    event Withdrawal(address indexed to, uint256 amount);
    event TokenWithdrawal(
        address indexed token,
        address indexed to,
        uint256 amount
    );
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function addStudent(
        string memory studentId,
        string memory fullName,
        string memory dateOfBirth,
        string memory gender,
        string memory major,
        string memory hometown,
        string memory permanentAddress
    ) public onlyOwner {
        require(
            !studentExistsByStudentId[studentId],
            "Student ID already exists"
        );

        studentCount++;

        students.push(
            Student({
                id: studentCount,
                studentId: studentId,
                fullName: fullName,
                dateOfBirth: dateOfBirth,
                gender: gender,
                major: major,
                hometown: hometown,
                permanentAddress: permanentAddress
            })
        );

        studentIndexById[studentCount] = students.length - 1;
        studentExistsByStudentId[studentId] = true;

        emit StudentAdded(studentCount, studentId, fullName);
    }

    function updateStudent(
        uint256 id,
        string memory studentId,
        string memory fullName,
        string memory dateOfBirth,
        string memory gender,
        string memory major,
        string memory hometown,
        string memory permanentAddress
    ) public onlyOwner {
        require(id > 0 && id <= studentCount, "Student ID does not exist");
        uint256 index = studentIndexById[id];
        require(index != 0 || (id == students[0].id), "Student not found");

        Student storage studentToUpdate = students[index];

        if (!compareStrings(studentToUpdate.studentId, studentId)) {
            delete studentExistsByStudentId[studentToUpdate.studentId];
            require(
                !studentExistsByStudentId[studentId],
                "Student ID already exists"
            );
            studentExistsByStudentId[studentId] = true;
        }

        studentToUpdate.studentId = studentId;
        studentToUpdate.fullName = fullName;
        studentToUpdate.dateOfBirth = dateOfBirth;
        studentToUpdate.gender = gender;
        studentToUpdate.major = major;
        studentToUpdate.hometown = hometown;
        studentToUpdate.permanentAddress = permanentAddress;

        emit StudentUpdated(id, studentId, fullName);
    }

    function deleteStudent(uint256 id) public onlyOwner {
        require(id > 0 && id <= studentCount, "Student ID does not exist");
        require(
            studentIndexById[id] != 0 || (id == students[0].id),
            "Student not found"
        );

        uint256 index = studentIndexById[id];
        Student memory studentToDelete = students[index];

        uint256 lastIndex = students.length - 1;
        if (index != lastIndex) {
            Student memory lastStudent = students[lastIndex];
            students[index] = lastStudent;
            studentIndexById[lastStudent.id] = index;
        }

        students.pop();

        delete studentIndexById[id];
        delete studentExistsByStudentId[studentToDelete.studentId];

        emit StudentDeleted(id, studentToDelete.studentId);
    }

    function searchStudentsByName(
        string memory name,
        uint256 page
    ) public view returns (Student[] memory results) {
        uint256 pageSize = 10;
        uint256 startIndex = (page - 1) * pageSize;
        uint256 matchCount = 0;

        for (uint256 i = 0; i < students.length; i++) {
            if (containsSubstring(students[i].fullName, name)) {
                matchCount++;
            }
        }

        results = new Student[](matchCount > pageSize ? pageSize : matchCount);
        uint256 resultIndex = 0;
        uint256 currentCount = 0;

        for (
            uint256 i = 0;
            i < students.length && resultIndex < results.length;
            i++
        ) {
            if (containsSubstring(students[i].fullName, name)) {
                if (currentCount >= startIndex && resultIndex < pageSize) {
                    results[resultIndex] = students[i];
                    resultIndex++;
                }
                currentCount++;
            }
        }
    }

    function getAllStudents(
        uint256 page
    ) public view returns (Student[] memory results) {
        uint256 pageSize = 10;
        uint256 totalStudents = students.length;
        uint256 startIndex = (page - 1) * pageSize;

        uint256 resultSize = (startIndex + pageSize > totalStudents)
            ? totalStudents - startIndex
            : pageSize;

        results = new Student[](resultSize);

        for (uint256 i = 0; i < resultSize; i++) {
            results[i] = students[startIndex + i];
        }
    }

    function compareStrings(
        string memory a,
        string memory b
    ) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function containsSubstring(
        string memory fullString,
        string memory subString
    ) internal pure returns (bool) {
        bytes memory fullStringBytes = bytes(fullString);
        bytes memory subStringBytes = bytes(subString);

        if (subStringBytes.length > fullStringBytes.length) {
            return false;
        }

        for (
            uint256 i = 0;
            i <= fullStringBytes.length - subStringBytes.length;
            i++
        ) {
            bool matchFound = true;
            for (uint256 j = 0; j < subStringBytes.length; j++) {
                if (fullStringBytes[i + j] != subStringBytes[j]) {
                    matchFound = false;
                    break;
                }
            }
            if (matchFound) {
                return true;
            }
        }
        return false;
    }

    function getTotalStudents() public view returns (uint256) {
        return students.length;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }

    function withdraw(uint256 amount) public onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        payable(owner).transfer(amount);
        emit Withdrawal(owner, amount);
    }

    function withdrawToken(address token, uint256 amount) public onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance >= amount, "Insufficient token balance");
        tokenContract.transfer(owner, amount);
        emit TokenWithdrawal(token, owner, amount);
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    receive() external payable {}
}
