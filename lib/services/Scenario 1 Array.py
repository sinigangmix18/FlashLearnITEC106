#include <stdio.h>
#include <string.h>

#define MAX_STUDENTS 100

typedef struct {
    int    id;
    char   name[50];
    char   course[30];
} Student;

/* Global array and count */
Student roster[MAX_STUDENTS];
int     count = 0;

/* Add a student to the roster */
int enroll(int id, const char *name, const char *course) {
    if (count >= MAX_STUDENTS) {
        printf("  [Error] Roster is full.\n");
        return 0;
    }
    roster[count].id = id;
    strncpy(roster[count].name,   name,   sizeof(roster[0].name)   - 1);
    strncpy(roster[count].course, course, sizeof(roster[0].course) - 1);
    roster[count].name[sizeof(roster[0].name) - 1]     = '\0';
    roster[count].course[sizeof(roster[0].course) - 1] = '\0';
    count++;
    return 1;
}

/* Display all enrolled students — O(n) */
void display_all(void) {
    if (count == 0) {
        printf("  (No students enrolled)\n");
        return;
    }
    printf("  %-6s %-25s %-20s\n", "ID", "Name", "Course");
    printf("  %-6s %-25s %-20s\n", "------", "-------------------------", "--------------------");
    for (int i = 0; i < count; i++) {
        printf("  %-6d %-25s %-20s\n",
               roster[i].id,
               roster[i].name,
               roster[i].course);
    }
}

/* Access student by index — O(1) */
void access_by_index(int idx) {
    if (idx < 0 || idx >= count) {
        printf("  [Error] Index %d out of range.\n", idx);
        return;
    }
    printf("  Index %d -> ID: %d | Name: %s | Course: %s\n",
           idx,
           roster[idx].id,
           roster[idx].name,
           roster[idx].course);
}

int main(void) {
    printf("=== Scenario 1: Array — Maintaining Enrolled Students ===\n\n");

    /* Enroll students */
    printf("Enrolling students...\n");
    enroll(1001, "Ana Reyes",     "BSCS");
    enroll(1002, "Ben Santos",    "BSIT");
    enroll(1003, "Clara Dizon",   "BSCS");
    enroll(1004, "David Lim",     "BSECE");
    enroll(1005, "Elena Cruz",    "BSIT");

    printf("\nCurrent roster (count = %d):\n", count);
    display_all();

    /* Demonstrate O(1) random access */
    printf("\nDirect access by index (O(1)):\n");
    access_by_index(0);
    access_by_index(2);
    access_by_index(4);

    return 0;
}