import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Employee Profile View Widget - Can be used by admin to view employee profiles
class EmployeeProfileView extends StatefulWidget {
  final Map<String, dynamic> employeeData;
  final VoidCallback onBack;
  final bool
      isViewOnly; // true when admin is viewing, false when user edits own profile

  const EmployeeProfileView({
    Key? key,
    required this.employeeData,
    required this.onBack,
    this.isViewOnly = true,
  }) : super(key: key);

  @override
  State<EmployeeProfileView> createState() => _EmployeeProfileViewState();
}

class _EmployeeProfileViewState extends State<EmployeeProfileView> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? employeeDetails;
  bool isLoading = true;

  // Controllers for editing (only used if not view-only)
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _contactNumberController =
      TextEditingController();
  final TextEditingController _bloodTypeController = TextEditingController();
  final TextEditingController _allergiesController = TextEditingController();
  final TextEditingController _medicalConditionsController =
      TextEditingController();
  final TextEditingController _disabilitiesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEmployeeDetails();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _addressController.dispose();
    _contactNumberController.dispose();
    _bloodTypeController.dispose();
    _allergiesController.dispose();
    _medicalConditionsController.dispose();
    _disabilitiesController.dispose();
    super.dispose();
  }

  Future<void> _loadEmployeeDetails() async {
    try {
      setState(() => isLoading = true);

      final email = widget.employeeData['email'];

      // Get User data
      final userResponse = await supabase
          .from('User')
          .select('id, email, person_id')
          .eq('email', email)
          .single();

      final personId = userResponse['person_id'];

      // Get Organization_User data
      final orgUserResponse = await supabase
          .from('Organization_User')
          .select('position, department')
          .eq('user_id', userResponse['id'])
          .single();

      // Get Person data
      final personResponse =
          await supabase.from('Person').select().eq('id', personId).single();

      setState(() {
        employeeDetails = {
          ...personResponse,
          'email': email,
          'position': orgUserResponse['position'],
          'department': orgUserResponse['department'],
          'user_id': userResponse['id'],
        };
        isLoading = false;

        // Initialize controllers
        _firstNameController.text = employeeDetails!['first_name'] ?? '';
        _middleNameController.text = employeeDetails!['middle_name'] ?? '';
        _lastNameController.text = employeeDetails!['last_name'] ?? '';
        _addressController.text = employeeDetails!['address'] ?? '';
        _contactNumberController.text =
            employeeDetails!['contact_number'] ?? '';
        _bloodTypeController.text = employeeDetails!['blood_type'] ?? '';
        _allergiesController.text = employeeDetails!['allergies'] ?? '';
        _medicalConditionsController.text =
            employeeDetails!['medical_conditions'] ?? '';
        _disabilitiesController.text = employeeDetails!['disabilities'] ?? '';
      });
    } catch (e) {
      print('Error loading employee details: $e');
      setState(() => isLoading = false);
      _showSnackBar('Error loading employee details: $e');
    }
  }

  Future<void> _updateEmployeeData() async {
    try {
      await supabase.from('Person').update({
        'first_name': _firstNameController.text.trim(),
        'middle_name': _middleNameController.text.trim(),
        'last_name': _lastNameController.text.trim(),
        'address': _addressController.text.trim(),
        'contact_number': _contactNumberController.text.trim(),
        'blood_type': _bloodTypeController.text.trim(),
        'allergies': _allergiesController.text.trim(),
        'medical_conditions': _medicalConditionsController.text.trim(),
        'disabilities': _disabilitiesController.text.trim(),
      }).eq('id', employeeDetails!['id']);

      await _loadEmployeeDetails();

      if (mounted) {
        Navigator.of(context).pop();
        _showSnackBar('Profile updated successfully!');
      }
    } catch (e) {
      _showSnackBar('Error updating profile: $e');
    }
  }

  String _formatDateTime(String? dateTimeString) {
    if (dateTimeString == null) return 'Not available';
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final day = dateTime.day.toString().padLeft(2, '0');
      final month = dateTime.month.toString().padLeft(2, '0');
      final year = dateTime.year;
      final hour = dateTime.hour.toString().padLeft(2, '0');
      final minute = dateTime.minute.toString().padLeft(2, '0');
      return '$day/$month/$year $hour:$minute';
    } catch (e) {
      return 'Invalid date';
    }
  }

  String _getFullName() {
    if (employeeDetails == null)
      return widget.employeeData['name'] ?? 'Unknown';

    final firstName = employeeDetails!['first_name'] ?? '';
    final middleName = employeeDetails!['middle_name'] ?? '';
    final lastName = employeeDetails!['last_name'] ?? '';

    return '$firstName ${middleName.isNotEmpty ? '$middleName ' : ''}$lastName'
        .trim();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF4A8B3A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Container(
        height: 400,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF4A8B3A)),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                    style: IconButton.styleFrom(
                      foregroundColor: const Color(0xFF4A8B3A),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildEmployeeAvatar(radius: 20),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getFullName(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF495057),
                        ),
                      ),
                      Text(
                        widget.employeeData['email'] ?? '',
                        style: const TextStyle(
                          color: Color(0xFF6C757D),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (!widget.isViewOnly)
                ElevatedButton.icon(
                  onPressed: () => _showEditDialog(context),
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Edit Profile'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A8B3A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(height: 24),

          // Profile Header Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildEmployeeAvatar(radius: 50),
                const SizedBox(height: 16),
                Text(
                  _getFullName(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF495057),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A8B3A).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    employeeDetails?['position'] ??
                        widget.employeeData['role'] ??
                        'Staff',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF4A8B3A),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    employeeDetails?['department'] ??
                        widget.employeeData['department'] ??
                        'General',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Personal Information Section
          const Text(
            'Personal Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF495057),
            ),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Email Address',
            widget.employeeData['email'] ?? 'Not specified',
            Icons.email,
            const Color(0xFF6BA85A),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Contact Number',
            employeeDetails?['contact_number'] ??
                widget.employeeData['phone'] ??
                'Not specified',
            Icons.phone,
            Colors.blue,
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Address',
            employeeDetails?['address'] ?? 'Not specified',
            Icons.location_on,
            Colors.orange,
            isMultiline: true,
          ),

          const SizedBox(height: 24),

          // Medical Information Section
          const Text(
            'Medical Information',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF495057),
            ),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Blood Type',
            employeeDetails?['blood_type'] ?? 'Not specified',
            Icons.bloodtype,
            Colors.red,
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Allergies',
            employeeDetails?['allergies'] ?? 'None specified',
            Icons.warning,
            Colors.orange,
            isMultiline: true,
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Medical Conditions',
            employeeDetails?['medical_conditions'] ?? 'None specified',
            Icons.medical_services,
            Colors.purple,
            isMultiline: true,
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            'Disabilities',
            employeeDetails?['disabilities'] ?? 'None specified',
            Icons.accessibility,
            Colors.blue,
            isMultiline: true,
          ),

          const SizedBox(height: 12),

          _buildInfoCard(
            'Member Since',
            _formatDateTime(employeeDetails?['created_at']),
            Icons.calendar_today,
            const Color(0xFF6C757D),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeAvatar({double radius = 20}) {
    final imageUrl = employeeDetails?['image'] ?? widget.employeeData['image'];
    final name = _getFullName();

    if (imageUrl != null && imageUrl.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF4A8B3A), width: 3),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFF4A8B3A),
          child: ClipOval(
            child: Image.network(
              imageUrl,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: radius * 2,
                  height: radius * 2,
                  color: const Color(0xFF4A8B3A),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: radius * 0.6,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF4A8B3A), width: 3),
        ),
        child: CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFF4A8B3A),
          child: Text(
            name.isNotEmpty ? name[0] : '?',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: radius * 0.6,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildInfoCard(
    String title,
    String content,
    IconData icon,
    Color iconColor, {
    bool isMultiline = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment:
            isMultiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6C757D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  content,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF495057),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: isMultiline ? null : 2,
                  overflow: isMultiline ? null : TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          backgroundColor: const Color(0xFFF8F9FA),
          title: const Text(
            'Edit Profile',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: Color(0xFF495057),
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(
                    controller: _firstNameController,
                    label: 'First Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _middleNameController,
                    label: 'Middle Name (Optional)',
                    icon: Icons.person_outline,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _lastNameController,
                    label: 'Last Name',
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _contactNumberController,
                    label: 'Contact Number',
                    icon: Icons.phone,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _addressController,
                    label: 'Address',
                    icon: Icons.location_on,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _bloodTypeController,
                    label: 'Blood Type',
                    icon: Icons.bloodtype,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _allergiesController,
                    label: 'Allergies',
                    icon: Icons.warning,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _medicalConditionsController,
                    label: 'Medical Conditions',
                    icon: Icons.medical_services,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _disabilitiesController,
                    label: 'Disabilities',
                    icon: Icons.accessibility,
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6C757D)),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: _updateEmployeeData,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A8B3A),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14, color: Color(0xFF495057)),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13, color: Color(0xFF6C757D)),
        prefixIcon: Icon(icon, color: const Color(0xFF6C757D), size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF4A8B3A), width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}
